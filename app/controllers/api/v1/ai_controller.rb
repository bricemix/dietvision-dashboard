module Api
  module V1
    class AiController < BaseController
      before_action :check_scan_limit!, only: %i[analyze]
      before_action :check_chat_limit!, only: %i[coach]
      before_action :check_dishes_limit!, only: %i[dishes]

      # POST /api/v1/ai/analyze
      # Body: { image: "<base64 JPEG>", locale: "fr", model: "..." (optional) }
      def analyze
        text_only = params[:text_only] == true || params[:text_only] == "true"
        base64    = params[:image]
        desc      = params[:description].to_s.strip
        if !text_only && base64.blank?
          return render json: { error: "Image manquante" }, status: :bad_request
        end
        # Limite anti-abus : ~5 Mo binaire (base64 ≈ +33%).
        if !text_only && base64.to_s.bytesize > 7_000_000
          return render json: { error: "Image trop volumineuse (max ~5 Mo)" }, status: :payload_too_large
        end
        if text_only && desc.blank?
          return render json: { error: "Description manquante" }, status: :bad_request
        end

        locale    = sanitize_locale(params[:locale])
        meal_type = params[:meal_type].to_s.strip
        service   = OpenrouterService.new(user: current_user)
        result    = if text_only
          service.analyze_food_text(desc, meal_type: meal_type.presence, model: resolve_model(params[:model]), locale: locale)
        else
          service.analyze_food(base64, model: resolve_model(params[:model]), locale: locale, description: desc.presence)
        end

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
        result        = service.coach_chat(messages, profile: profile, model: resolve_model(params[:model]),
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
        # Plats : la sortie (3 plats + ingrédients + étapes) dépasse souvent
        # 1800 tokens et tronquait le JSON. On force une limite serveur large,
        # quelle que soit la valeur envoyée par le client.
        max_tokens = 3000
        profile    = params[:profile] || {}
        service    = OpenrouterService.new(user: current_user)
        result     = service.dish_recommendations(messages, profile: profile, model: resolve_model(params[:model]),
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

      # Modèles retirés d'OpenRouter : on ignore la valeur envoyee par l'app
      # (clients deja installes) et on retombe sur AppConfig (mis a jour cote serveur).
      DEPRECATED_MODELS = %w[
        google/gemini-2.0-flash-001
        google/gemini-pro-vision
        google/gemini-1.5-flash
      ].freeze

      # On ignore TOUJOURS le modèle envoyé par le client : le choix du modèle
      # est centralisé côté serveur (AppConfig / dashboard) selon le type de
      # requête (scan = vision_model, chat & plats = default_model).
      def resolve_model(_requested)
        nil
      end
    end
  end
end
