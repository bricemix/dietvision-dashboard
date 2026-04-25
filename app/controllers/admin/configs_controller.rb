module Admin
  class ConfigsController < BaseController
    def index
      @configs = AppConfig::KEYS.map { |k|
        { key: k, value: AppConfig.get(k), description: description_for(k) }
      }
    end

    def update
      params.require(:configs).each do |key, value|
        next unless AppConfig::KEYS.include?(key)
        AppConfig.set(key, value.strip)
      end
      redirect_to admin_configs_path, notice: "Configuration sauvegardée"
    end

    # Test de connexion OpenRouter
    def test_openrouter
      key = AppConfig.openrouter_api_key
      return render json: { error: "Clé API manquante" }, status: :bad_request unless key.present?

      conn = Faraday.new(url: "https://openrouter.ai/api/v1") do |f|
        f.response :json
        f.adapter  Faraday.default_adapter
      end

      res = conn.get("/models") do |req|
        req.headers["Authorization"] = "Bearer #{key}"
      end

      if res.success?
        models = res.body["data"]&.map { |m| m["id"] }&.first(10) || []
        render json: { ok: true, models: models }
      else
        render json: { error: "Erreur API (#{res.status})" }
      end
    rescue => e
      render json: { error: e.message }
    end

    private

    def description_for(key)
      {
        "openrouter_api_key"      => "Clé API OpenRouter (sk-or-v1-...)",
        "openrouter_default_model" => "Modèle texte par défaut (ex: google/gemini-2.0-flash-001)",
        "openrouter_vision_model"  => "Modèle vision pour analyse photo",
        "free_plan_daily_limit"    => "Nb d'appels IA/jour — plan gratuit",
        "premium_plan_daily_limit" => "Nb d'appels IA/jour — plan premium",
        "cinetpay_api_key"         => "Clé API CinetPay",
        "cinetpay_site_id"         => "Site ID CinetPay",
        "app_name"                 => "Nom de l'application",
        "support_email"            => "Email support"
      }[key]
    end
  end
end
