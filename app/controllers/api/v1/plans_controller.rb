module Api
  module V1
    class PlansController < BaseController
      skip_authentication :index

      # GET /api/v1/plans
      def index
        plans = Plan.active.map { |p| serialize(p) }
        render json: plans
      end

      private

      def serialize(plan)
        {
          id:                        plan.id,
          name:                      plan.name,
          slug:                      plan.slug,
          description:               plan.description,
          price_ariary:              plan.price_ariary,
          price_usd_cents:           plan.price_usd_cents,
          price_eur_cents:           plan.price_eur_cents,
          price_formatted:           plan.price_formatted,
          original_price_eur_cents:  plan.respond_to?(:original_price_eur_cents) ? plan.original_price_eur_cents.to_i : 0,
          billing_frequency:         plan.billing_frequency,
          frequency_label:           plan.frequency_label,
          features:                  plan.features,
          features_excluded:         plan.respond_to?(:features_excluded) ? plan.features_excluded : [],
          operators:                 plan.operators,
          badge:                     plan.badge,
          cta_label:                 plan.respond_to?(:cta_label) && plan.cta_label.present? ? plan.cta_label : "Essayer 7 jours gratuits",
          cta_style:                 plan.respond_to?(:cta_style) && plan.cta_style.present? ? plan.cta_style : "outline",
          stripe_price_id:           plan.stripe_price_id,
          prices:                    plan.prices,
          translations:              plan.respond_to?(:translations) ? plan.translations : {},
          email_report_frequency:    plan.respond_to?(:email_report_frequency) ? plan.email_report_frequency : 'never'
        }
      end
    end
  end
end
