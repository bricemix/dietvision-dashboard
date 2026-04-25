module Api
  module V1
    class AiController < BaseController
      before_action :check_daily_limit!

      # POST /api/v1/ai/analyze
      # Body: { image: "<base64 JPEG>", model: "..." (optional) }
      def analyze
        base64 = params[:image]
        return render json: { error: "Image manquante" }, status: :bad_request if base64.blank?

        service = OpenrouterService.new(user: current_user)
        result  = service.analyze_food(base64, model: params[:model])

        if result[:error]
          render json: result, status: :unprocessable_entity
        else
          render json: result
        end
      end

      # POST /api/v1/ai/coach
      # Body: { messages: [{role: "user", content: "..."}], profile: {...} }
      def coach
        messages = params[:messages]
        return render json: { error: "Messages manquants" }, status: :bad_request if messages.blank?

        profile = params[:profile] || {}
        service = OpenrouterService.new(user: current_user)
        result  = service.coach_chat(messages, profile: profile, model: params[:model])

        if result[:error]
          render json: result, status: :unprocessable_entity
        else
          render json: result
        end
      end
    end
  end
end
