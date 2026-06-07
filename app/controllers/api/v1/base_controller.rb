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

      def check_scan_limit!
        limit = _scan_limit_for(current_user)
        return if limit >= 999
        used = ApiUsage.where(user: current_user, endpoint: "analyze_food", status: "success").today.count
        if used >= limit
          render json: {
            error:            "Limite de scans journalière atteinte (#{used}/#{limit})",
            upgrade_required: !current_user.premium? && !current_user.pro?,
            plan:             current_user.plan.to_s,
            limit:            limit,
            used:             used,
            limit_type:       "scan"
          }, status: :too_many_requests
        end
      end

      def check_chat_limit!
        limit = _chat_limit_for(current_user)
        return if limit >= 999
        used = ApiUsage.where(user: current_user, endpoint: "coach_chat", status: "success").today.count
        if used >= limit
          render json: {
            error:            "Limite de messages journalière atteinte (#{used}/#{limit})",
            upgrade_required: !current_user.premium? && !current_user.pro?,
            plan:             current_user.plan.to_s,
            limit:            limit,
            used:             used,
            limit_type:       "chat"
          }, status: :too_many_requests
        end
      end

      def _scan_limit_for(user)
        if    user.vip?     then 999
        elsif user.premium? then AppConfig.premium_scan_daily_limit
        elsif user.pro?     then AppConfig.pro_scan_daily_limit
        elsif user.in_trial? || (user.plan.to_s == "starter" && user.subscription_expires_at&.future?)
          AppConfig.starter_scan_daily_limit
        else
          AppConfig.free_scan_daily_limit
        end
      end

      def _chat_limit_for(user)
        if    user.vip?     then 999
        elsif user.premium? then AppConfig.premium_chat_daily_limit
        elsif user.pro?     then AppConfig.pro_chat_daily_limit
        elsif user.in_trial? || (user.plan.to_s == "starter" && user.subscription_expires_at&.future?)
          AppConfig.starter_chat_daily_limit
        else
          AppConfig.free_chat_daily_limit
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

        # VIP / illimité : pas de comptage ni de blocage
        return if limit >= 999

        used = ApiUsage.where(user: current_user, endpoint: "dish_recommendation", status: "success").today.count
        if used >= limit
          render json: {
            error:            "Limite de plats recommandés atteinte (#{used}/#{limit} aujourd'hui).",
            upgrade_required: !current_user.premium?,
            plan:             current_user.plan.to_s,
            limit:            limit,
            used:             used,
            limit_type:       "dishes",
            feature:          "dish_recommendation"
          }, status: :too_many_requests
        end
      end
    end
  end
end
