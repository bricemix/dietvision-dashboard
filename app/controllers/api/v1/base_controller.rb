module Api
  module V1
    class BaseController < ActionController::API
      include JwtAuthenticatable

      rescue_from ActiveRecord::RecordNotFound do |e|
        render json: { error: "Ressource introuvable" }, status: :not_found
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def check_daily_limit!
        limit = if current_user.vip?
          AppConfig.vip_daily_limit
        elsif current_user.premium?
          AppConfig.premium_daily_limit
        elsif current_user.pro?
          AppConfig.pro_daily_limit
        elsif current_user.in_trial?
          AppConfig.trial_daily_limit
        else
          AppConfig.free_daily_limit
        end
        used = ApiUsage.where(user: current_user).today.count
        if used >= limit
          render json: {
            error: "Limite journalière atteinte (#{used}/#{limit})",
            upgrade_required: !current_user.premium?
          }, status: :too_many_requests
        end
      end

      # Limite spécifique aux plats recommandés (rafraîchissements/jour)
      # Free/Trial = 0 (feature verrouillée). Pro = 5, Premium = 15, VIP = illimité.
      def check_dishes_limit!
        limit = if current_user.vip?
          AppConfig.vip_dishes_limit
        elsif current_user.premium?
          AppConfig.premium_dishes_limit
        elsif current_user.pro?
          AppConfig.pro_dishes_limit
        else
          # Free ou Trial : feature non disponible
          0
        end

        if limit == 0
          return render json: {
            error: "Les plats recommandés par l'IA sont disponibles à partir du plan Pro.",
            upgrade_required: true,
            feature: "dish_recommendation"
          }, status: :forbidden
        end

        used = ApiUsage.where(user: current_user, endpoint: "dish_recommendation").today.count
        if used >= limit
          render json: {
            error: "Limite de plats recommandés atteinte (#{used}/#{limit} aujourd'hui).",
            upgrade_required: !current_user.premium?,
            feature: "dish_recommendation"
          }, status: :too_many_requests
        end
      end
    end
  end
end
