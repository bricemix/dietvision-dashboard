module Admin
  class PlansController < BaseController
    before_action :set_plan, only: %i[edit update destroy activate deactivate sync_stripe]

    def index
      @plans = Plan.order(:position, :id)
    end

    def new
      @plan = Plan.new(
        status: "draft",
        billing_frequency: "monthly",
        operators: Plan::OPERATORS
      )
      @all_features    = all_unique_features
      @existing_plans  = Plan.order(:position, :id).map { |p|
        { id: p.id, name: p.name, slug: p.slug,
          billing_frequency: p.billing_frequency,
          description: p.description.to_s,
          price_ariary: p.price_ariary,
          prices: p.prices,
          badge: p.badge.to_s,
          cta_label: p.cta_label.to_s,
          cta_style: p.cta_style.to_s,
          features: p.features,
          features_excluded: p.features_excluded,
          stripe_price_id: p.stripe_price_id.to_s,
          translations: p.translations }
      }
    end

    def create
      @plan = Plan.new(plan_params.except(:operators))
      @plan.features           = features_from_params
      @plan.features_excluded  = features_excluded_from_params
      @plan.operators          = Array(params.dig(:plan, :operators))
      @plan.prices             = prices_from_params
      @plan.original_price_eur_cents = original_price_from_params
      @plan.translations       = translations_from_params
      if @plan.save
        AdminLog.log(admin: current_admin, action: "create_plan", resource: @plan, ip: request.remote_ip)
        redirect_to admin_plans_path, notice: "Plan \"#{@plan.name}\" créé"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @all_features = all_unique_features
    end

    def update
      @plan.features           = features_from_params
      @plan.features_excluded  = features_excluded_from_params
      @plan.operators          = Array(params.dig(:plan, :operators))
      @plan.prices             = prices_from_params
      @plan.original_price_eur_cents = original_price_from_params
      @plan.translations       = translations_from_params
      if @plan.update(plan_params.except(:operators))
        AdminLog.log(admin: current_admin, action: "update_plan", resource: @plan, ip: request.remote_ip)
        redirect_to admin_plans_path, notice: "Plan mis à jour"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      name = @plan.name
      @plan.destroy
      AdminLog.log(admin: current_admin, action: "delete_plan", details: { name: name }, ip: request.remote_ip)
      redirect_to admin_plans_path, notice: "Plan supprimé"
    end

    def activate
      @plan.update!(status: "active")
      AdminLog.log(admin: current_admin, action: "activate_plan", resource: @plan, ip: request.remote_ip)
      redirect_to admin_plans_path, notice: "Plan activé — visible dans l'app"
    end

    def deactivate
      @plan.update!(status: "inactive")
      AdminLog.log(admin: current_admin, action: "deactivate_plan", resource: @plan, ip: request.remote_ip)
      redirect_to admin_plans_path, notice: "Plan désactivé"
    end

    # POST /admin/plans/:id/sync_stripe
    # Crée (ou recrée) le produit + prix Stripe pour ce plan depuis le dashboard Rails.
    def sync_stripe
      if @plan.price_eur_cents.to_i == 0
        return redirect_to admin_plans_path, alert: "Définissez d'abord un prix EUR avant de synchroniser avec Stripe."
      end

      price_id = StripeService.new.sync_plan_to_stripe(@plan)
      AdminLog.log(admin: current_admin, action: "sync_stripe_plan", resource: @plan,
                   details: { stripe_price_id: price_id }, ip: request.remote_ip)
      redirect_to admin_plans_path, notice: "✓ Plan \"#{@plan.name}\" synchronisé avec Stripe (#{price_id})"

    rescue Stripe::StripeError => e
      redirect_to admin_plans_path, alert: "Erreur Stripe : #{e.message}"
    rescue ArgumentError => e
      redirect_to admin_plans_path, alert: e.message
    end

    # POST /admin/plans/sync_all_stripe
    # Synchronise tous les plans ayant un prix EUR > 0 avec Stripe.
    def sync_all_stripe
      service   = StripeService.new
      synced    = []
      skipped   = []
      errors    = []

      Plan.order(:position, :id).each do |plan|
        if plan.price_eur_cents.to_i == 0
          skipped << plan.name
          next
        end

        begin
          price_id = service.sync_plan_to_stripe(plan)
          synced << "#{plan.name} (#{price_id})"
        rescue Stripe::StripeError, ArgumentError => e
          errors << "#{plan.name} : #{e.message}"
        end
      end

      AdminLog.log(admin: current_admin, action: "sync_all_stripe",
                   details: { synced: synced.size, skipped: skipped.size, errors: errors.size },
                   ip: request.remote_ip)

      parts = []
      parts << "✓ #{synced.size} plan(s) synchronisé(s) : #{synced.join(', ')}" if synced.any?
      parts << "⚠ #{skipped.size} ignoré(s) (sans prix EUR) : #{skipped.join(', ')}" if skipped.any?

      if errors.any?
        redirect_to admin_plans_path,
                    alert: "#{parts.join(' — ')} — #{errors.size} erreur(s) : #{errors.join(' | ')}"
      else
        redirect_to admin_plans_path,
                    notice: parts.join(' — ').presence || "Aucun plan à synchroniser"
      end
    end

    private

    def set_plan
      @plan = Plan.find(params[:id])
    end

    def plan_params
      params.require(:plan).permit(:name, :slug, :description, :price_ariary,
                                   :billing_frequency, :badge, :status, :position,
                                   :stripe_price_id, :price_usd_cents,
                                   :cta_label, :cta_style,
                                   :email_report_frequency, :email_report_day,
                                   operators: [])
    end

    def features_from_params
      Array(params.dig(:plan, :features)).reject(&:blank?)
    end

    def features_excluded_from_params
      Array(params.dig(:plan, :features_excluded)).reject(&:blank?)
    end

    def original_price_from_params
      raw = params.dig(:plan, :original_price_eur_cents).to_s.strip
      return 0 if raw.blank?
      raw.include?(".") ? (raw.to_f * 100).round : raw.to_i
    end

    # Builds translations hash from nested params:
    # plan[translations][fr][name], plan[translations][fr][features][], etc.
    def translations_from_params
      raw = params.dig(:plan, :translations)
      return {} if raw.blank?
      h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.to_h : raw.to_h
      h.each_with_object({}) do |(lang, trans), result|
        next unless Plan::LOCALES.include?(lang.to_s)
        result[lang.to_s] = {
          "name"              => trans["name"].to_s.strip,
          "description"       => trans["description"].to_s.strip,
          "features"          => Array(trans["features"]).reject(&:blank?),
          "features_excluded" => Array(trans["features_excluded"]).reject(&:blank?),
          "cta_label"         => trans["cta_label"].to_s.strip
        }.reject { |_, v| v.blank? }
      end
    end

    # Extrait les prix par devise depuis le formulaire et filtre les zéros.
    # Retourne { "EUR" => 399, "USD" => 499, "XOF" => 3025 }
    # Format accepté : "3.99" (converti en centimes) ou nombre entier
    def all_unique_features
      Plan.all.flat_map { |p|
        p.features + p.features_excluded +
        p.translations.values.flat_map { |t|
          Array(t["features"]) + Array(t["features_excluded"])
        }
      }.map(&:strip).reject(&:blank?).uniq.sort
    end

    def prices_from_params
      raw = params.dig(:plan, :prices)
      return {} if raw.blank?
      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      hash.transform_values do |v|
        str = v.to_s.strip
        if str.include?(".") && str.match?(/^\d+\.\d+$/)
          (str.to_f * 100).round
        else
          str.to_i
        end
      end.reject { |_, v| v.zero? }
    end
  end
end
