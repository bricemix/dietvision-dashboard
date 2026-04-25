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
        limit = current_user.premium? ? AppConfig.premium_daily_limit : AppConfig.free_daily_limit
        used  = ApiUsage.where(user: current_user).today.count
        if used >= limit
          render json: {
            error: "Limite journalière atteinte (#{used}/#{limit})",
            upgrade_required: !current_user.premium?
          }, status: :too_many_requests
        end
      end
    end
  end
end
