module Api
  module V1
    # Public endpoint — configuration visible par le site web et l'app mobile.
    # Aucune donnée sensible ici.
    class ConfigController < BaseController
      skip_authentication :show

      # GET /api/v1/config
      def show
        trial_days    = AppConfig.trial_period_days
        trial_enabled = AppConfig.trial_enabled?

        render json: {
          trial_enabled:  trial_enabled,
          trial_days:     trial_days,
          # Afficher 0 si non configuré (le site n'affichera pas la bannière essai)
          has_trial:      trial_enabled && trial_days > 0
        }
      end
    end
  end
end
