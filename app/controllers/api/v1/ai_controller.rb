module Api
  module V1
    class AiController < BaseController
      before_action :check_daily_limit!, only: %i[analyze coach]
      before_action :check_dishes_limit!, only: %i[dishes]

      # POST /api/v1/ai/analyze
      # Body: { image: "<base64 JPEG>", locale: "fr", model: "..." (optional) }
      def analyze
        base64 = params[:image]
        return render json: { error: "Image manquante" }, status: :bad_request if base64.blank?

        locale  = sanitize_locale(params[:locale])
        service = OpenrouterService.new(user: current_user)
        result  = service.analyze_food(base64, model: params[:model], locale: locale)

        if result[:error]
          render json: result, status: :unprocessable_entity
        else
          render json: result
        end
      end

      # POST /api/v1/ai/coach
      # Body: { messages: [{role: "user", content: "..."}], profile: {...}, locale: "fr",
      #         today_context: { kcal_consumed:, kcal_remaining:, protein_g:, meals: [...] } }
      def coach
        messages = params[:messages]
        return render json: { error: "Messages manquants" }, status: :bad_request if messages.blank?

        profile       = params[:profile] || {}
        locale        = sanitize_locale(params[:locale])
        max_tokens    = params[:max_tokens].to_i.clamp(100, 2000).then { |v| v > 0 ? v : nil }
        today_context = (params[:today_context] || {}).to_unsafe_h
        service       = OpenrouterService.new(user: current_user)
        result        = service.coach_chat(messages, profile: profile, model: params[:model],
                                           locale: locale, max_tokens: max_tokens,
                                           today_context: today_context)

        if result[:error]
          render json: result, status: :unprocessable_entity
        else
          render json: result
        end
      end
      # POST /api/v1/ai/dishes
      # Body: { messages: [{role:"user", content:"..."}], profile: {...}, locale: "fr", max_tokens: 1200 }
      # Tracé séparément (endpoint: dish_recommendation) avec limite propre par plan.
      def dishes
        messages = params[:messages]
        return render json: { error: "Messages manquants" }, status: :bad_request if messages.blank?

        locale     = sanitize_locale(params[:locale])
        max_tokens = params[:max_tokens].to_i.clamp(100, 2000).then { |v| v > 0 ? v : nil }
        profile    = params[:profile] || {}
        service    = OpenrouterService.new(user: current_user)
        result     = service.dish_recommendations(messages, profile: profile, model: params[:model],
                                                  locale: locale, max_tokens: max_tokens)

        if result[:error]
          render json: result, status: :unprocessable_entity
        else
          render json: result
        end
      end

      private

      SUPPORTED_LOCALES = %w[fr en de es it pt nl].freeze

      def sanitize_locale(locale)
        l = locale.to_s.downcase.strip.split(/[-_]/).first
        SUPPORTED_LOCALES.include?(l) ? l : "fr"
      end
    end
  end
end
