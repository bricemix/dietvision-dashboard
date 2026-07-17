module Admin
  class PromoCodesController < BaseController
    before_action :set_promo_code, only: %i[show edit update destroy disable sync_stripe send_report_test]

    def index
      scope = PromoCode.order(created_at: :desc)
      case params[:status]
      when "expired"
        # Un code peut être expiré soit par statut manuel, soit par date passée
        # sans qu'un job planifié n'ait mis à jour la colonne `status` (voir PromoCode#effective_status).
        scope = scope.where(
          "status = ? OR (status = ? AND expires_at IS NOT NULL AND expires_at < ?)",
          "expired", "active", Time.current
        )
      when "active"
        scope = scope.where(status: "active")
                     .where("expires_at IS NULL OR expires_at >= ?", Time.current)
      when "disabled"
        scope = scope.where(status: "disabled")
      end
      @pagy, @promo_codes = pagy(scope, limit: 25)

      @total_active   = PromoCode.where(status: "active").count
      @total_uses     = PromoCode.sum(:uses_count)
      @unique_users_by_code = PromoCodeRedemption.group(:promo_code_id).distinct.count(:user_id)
    end

    # GET /admin/promo_codes/:id — détail des utilisateurs ayant utilisé ce code
    def show
      @redemptions   = @promo_code.promo_code_redemptions.includes(:user, :payment).order(created_at: :desc)
      @unique_users  = @redemptions.map(&:user_id).uniq.count
    end

    def new
      @promo_code = PromoCode.new(
        status: "active",
        discount_type: "percent",
        max_uses_per_user: 1
      )
    end

    def create
      @promo_code = PromoCode.new(promo_code_params)
      @promo_code.applicable_plans     = Array(params.dig(:promo_code, :applicable_plans)).reject(&:blank?)
      @promo_code.notification_emails  = params.dig(:promo_code, :notification_emails)
      if @promo_code.save
        AdminLog.log(admin: current_admin, action: "create_promo_code", resource: @promo_code, ip: request.remote_ip)
        stripe_notice = sync_to_stripe(@promo_code)
        redirect_to admin_promo_codes_path, notice: "Code promo #{@promo_code.code} créé#{stripe_notice}"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      @promo_code.applicable_plans    = Array(params.dig(:promo_code, :applicable_plans)).reject(&:blank?)
      @promo_code.notification_emails = params.dig(:promo_code, :notification_emails)
      if @promo_code.update(promo_code_params)
        stripe_notice = sync_to_stripe(@promo_code)
        redirect_to admin_promo_codes_path, notice: "Code mis à jour#{stripe_notice}"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Désactiver côté Stripe avant suppression
      if @promo_code.stripe_coupon_id.present?
        begin
          Stripe.api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"]
          Stripe::Coupon.delete(@promo_code.stripe_coupon_id)
        rescue Stripe::StripeError
          nil
        end
      end
      code = @promo_code.code
      @promo_code.destroy
      redirect_to admin_promo_codes_path, notice: "Code #{code} supprimé"
    end

    def sync_stripe
      begin
        # Force re-création : on remet stripe_promotion_code_id à nil pour que
        # sync_promo_code_to_stripe recrée un PromotionCode Stripe propre.
        # Le coupon existant est réutilisé si stripe_coupon_id est déjà présent.
        StripeService.new.sync_promo_code_to_stripe(@promo_code)
        AdminLog.log(admin: current_admin, action: "sync_stripe_promo_code", resource: @promo_code, ip: request.remote_ip)
        redirect_to admin_promo_codes_path,
                    notice: "✓ Code #{@promo_code.code} synchronisé avec Stripe (coupon #{@promo_code.stripe_coupon_id})"
      rescue => e
        redirect_to admin_promo_codes_path,
                    alert: "Sync Stripe échouée pour #{@promo_code.code} : #{e.message}"
      end
    end

    # POST /admin/promo_codes/:id/send_report_test
    # Envoie immédiatement un résumé test à l'adresse choisie (ou aux emails
    # déjà configurés sur le code si aucune adresse n'est précisée).
    def send_report_test
      recipient = params[:test_email].presence
      emails    = recipient ? [recipient] : @promo_code.notification_emails
      emails    = [current_admin.email] if emails.blank?

      since = 24.hours.ago
      redemptions_today = @promo_code.promo_code_redemptions.where(created_at: since..Time.current)

      PromoCodeMailer.daily_usage_report(
        promo_code:   @promo_code,
        emails:       emails,
        today_count:  redemptions_today.count,
        today_unique: redemptions_today.distinct.count(:user_id),
        total_uses:   @promo_code.uses_count,
        total_unique: @promo_code.promo_code_redemptions.distinct.count(:user_id)
      ).deliver_now

      redirect_back fallback_location: admin_promo_codes_path,
                    notice: "📤 Email test envoyé à #{emails.join(', ')}"
    rescue => e
      redirect_back fallback_location: admin_promo_codes_path,
                    alert: "Échec de l'envoi test : #{e.message}"
    end

    def disable
      @promo_code.update!(status: "disabled")
      # Désactiver le PromotionCode côté Stripe
      if @promo_code.stripe_promotion_code_id.present?
        begin
          Stripe.api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"]
          Stripe::PromotionCode.update(@promo_code.stripe_promotion_code_id, active: false)
        rescue Stripe::StripeError
          nil
        end
      end
      redirect_to admin_promo_codes_path, notice: "Code #{@promo_code.code} désactivé"
    end

    def bulk_generate
      prefix         = params[:prefix].to_s.upcase.gsub(/[^A-Z0-9]/, "")
      count          = [[params[:count].to_i, 1].max, 200].min
      discount_type  = params[:discount_type].presence_in(%w[percent fixed]) || "percent"
      discount_value = params[:discount_value].to_f
      expires_at     = params[:expires_at].present? ? Time.zone.parse(params[:expires_at]) : nil

      generated = PromoCode.generate_bulk!(
        count: count, prefix: prefix,
        discount_type: discount_type, discount_value: discount_value,
        expires_at: expires_at
      )
      AdminLog.log(admin: current_admin, action: "bulk_generate_promo_codes",
                   details: { count: generated.size, prefix: prefix }, ip: request.remote_ip)
      redirect_to admin_promo_codes_path, notice: "#{generated.size} codes générés"
    end

    private

    def set_promo_code
      @promo_code = PromoCode.find(params[:id])
    end

    # Synchronise le code promo vers Stripe. Retourne une notice textuelle.
    def sync_to_stripe(promo_code)
      StripeService.new.sync_promo_code_to_stripe(promo_code)
      " · synchronisé avec Stripe ✓"
    rescue => e
      Rails.logger.warn("Stripe promo sync failed: #{e.message}")
      " · (sync Stripe échouée : #{e.message})"
    end

    def promo_code_params
      params.require(:promo_code).permit(
        :code, :discount_type, :discount_value,
        :starts_at, :expires_at,
        :max_uses_total, :max_uses_per_user, :status
      )
    end
  end
end
