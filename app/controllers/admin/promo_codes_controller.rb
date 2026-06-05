module Admin
  class PromoCodesController < BaseController
    before_action :set_promo_code, only: %i[edit update destroy disable]

    def index
      scope = PromoCode.order(created_at: :desc)
      scope = scope.where(status: params[:status]) if params[:status].present?
      @pagy, @promo_codes = pagy(scope, limit: 25)

      @total_active   = PromoCode.where(status: "active").count
      @total_uses     = PromoCode.sum(:uses_count)
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
      @promo_code.applicable_plans = Array(params.dig(:promo_code, :applicable_plans)).reject(&:blank?)
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
      @promo_code.applicable_plans = Array(params.dig(:promo_code, :applicable_plans)).reject(&:blank?)
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
      count          = [ [ params[:count].to_i, 1 ].max, 200 ].min
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
