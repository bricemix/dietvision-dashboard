module Api
  module V1
    class PlansController < BaseController
      skip_authentication :index

      # GET /api/v1/plans
      # Respecte l'en-tête Accept-Language pour retourner le contenu dans la bonne langue.
      # Exemples : Accept-Language: de → DE, Accept-Language: fr → FR, Accept-Language: en → EN (= us)
      def index
        locale = detect_locale

        all_plans = Plan.active.to_a

        # Index des plans de base (mensuel, slug sans tiret) par slug.
        # Ex : {"pro" => #<Plan>, "premium" => #<Plan>, "vip" => #<Plan>}
        # Utilisé comme fallback pour les features des plans non-mensuel (pro-yearly, etc.)
        # qui ne stockent pas de features propres dans translations_json.
        base_plans = all_plans
          .select { |p| !p.slug.include?("-") }
          .index_by(&:slug)

        plans = all_plans.map { |p| serialize(p, locale, base_plans) }
        render json: plans
      end

      private

      # Extrait la locale depuis Accept-Language et la normalise vers nos locales supportées.
      # "de-DE,de;q=0.9" → "de" | "en-US" → "us" | "fr-FR" → "fr" | fallback → "us"
      def detect_locale
        raw = request.env["HTTP_ACCEPT_LANGUAGE"].to_s.downcase
        lang = raw.split(/[,;]/).first&.strip&.split("-")&.first || "us"
        case lang
        when "fr"        then "fr"
        when "de"        then "de"
        when "es", "pt"  then lang
        when "en"        then "us"
        else                  "us"
        end
      end

      def serialize(plan, locale = "us", base_plans = {})
        t = plan.translate(locale)

        # ── Features fallback ──────────────────────────────────────────────────
        # Les plans non-mensuel (pro-yearly, premium-quarterly…) ne stockent que
        # name + cta_label dans translations_json. Leurs features sont héritées
        # du plan de base mensuel du même tier (slug avant le premier tiret).
        #
        # IMPORTANT : on lit les translations BRUTES (pas via plan.translate() qui
        # masque le problème en retournant déjà le fallback FR depuis la colonne DB).
        raw_t = plan.translations[locale] || plan.translations["en"] || plan.translations["fr"] || {}
        features          = raw_t["features"].presence
        features_excluded = raw_t["features_excluded"].presence

        if (features.nil? || features_excluded.nil?) && plan.slug.include?("-")
          base_slug = plan.slug.split("-").first   # "pro-yearly" → "pro", "premium-quarterly" → "premium"
          base_plan = base_plans[base_slug]
          if base_plan
            base_raw_t = base_plan.translations[locale] || base_plan.translations["en"] || base_plan.translations["fr"] || {}
            features          ||= base_raw_t["features"].presence || base_plan.features
            features_excluded ||= base_raw_t["features_excluded"].presence || base_plan.features_excluded
          end
        end

        features          ||= plan.features
        features_excluded ||= plan.features_excluded

        {
          id:                        plan.id,
          name:                      t["name"],
          slug:                      plan.slug,
          description:               t["description"].presence || plan.translate("fr")["description"],
          price_ariary:              plan.price_ariary,
          price_usd_cents:           plan.price_usd_cents,
          price_eur_cents:           plan.price_eur_cents,
          price_formatted:           plan.price_formatted,
          original_price_eur_cents:  plan.respond_to?(:original_price_eur_cents) ? plan.original_price_eur_cents.to_i : 0,
          billing_frequency:         plan.billing_frequency,
          frequency_label:           plan.frequency_label,
          features:                  features,
          features_excluded:         features_excluded,
          operators:                 plan.operators,
          badge:                     plan.badge,
          cta_label:                 t["cta_label"].presence || "Essayer 7 jours gratuits",
          cta_style:                 plan.respond_to?(:cta_style) && plan.cta_style.present? ? plan.cta_style : "outline",
          stripe_price_id:           plan.stripe_price_id,
          prices:                    plan.prices,
          translations:              plan.translations,
          email_report_frequency:    plan.respond_to?(:email_report_frequency) ? plan.email_report_frequency : 'never'
        }
      end
    end
  end
end
