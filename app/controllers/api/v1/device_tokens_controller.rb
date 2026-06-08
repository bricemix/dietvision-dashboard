module Api
  module V1
    # Enregistrement des tokens FCM (push) par appareil.
    class DeviceTokensController < BaseController
      # POST /api/v1/device_tokens   Body: { token:, platform: "android"|"ios" }
      def create
        token    = params[:token].to_s.strip
        platform = params[:platform].to_s.strip
        platform = "android" unless DeviceToken::PLATFORMS.include?(platform)
        return render json: { error: "Token manquant" }, status: :bad_request if token.blank?

        dt = DeviceToken.find_or_initialize_by(token: token)
        dt.user         = current_user
        dt.platform     = platform
        dt.last_used_at = Time.current
        dt.save!
        render json: { ok: true }
      end

      # DELETE /api/v1/device_tokens   Body: { token: }
      def destroy
        token = params[:token].to_s.strip
        DeviceToken.where(token: token, user: current_user).delete_all if token.present?
        head :no_content
      end
    end
  end
end
