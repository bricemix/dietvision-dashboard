module Admin
  class ConfigsController < BaseController
    def index
      @configs = AppConfig::KEYS.map { |k|
        { key: k, value: AppConfig.get(k), description: description_for(k) }
      }
    end

    def update
      saved = 0
      params.require(:configs).each do |key, value|
        next unless AppConfig::KEYS.include?(key)
        next if value.blank?   # ne jamais écraser avec une valeur vide (champ password non rempli)
        AppConfig.set(key, value.strip)
        saved += 1
      end
      redirect_to admin_configs_path, notice: "#{saved} clé(s) sauvegardée(s)"
    end

    # Test de connexion OpenRouter
    def test_openrouter
      key = AppConfig.openrouter_api_key
      return render json: { error: "Clé API manquante — configurez openrouter_api_key" }, status: :bad_request unless key.present?

      # Trailing slash obligatoire pour que les chemins relatifs soient résolus correctement
      conn = Faraday.new(url: "https://openrouter.ai/api/v1/") do |f|
        f.options.timeout      = 15
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end

      # "models" sans "/" initial → résolu en https://openrouter.ai/api/v1/models
      res = conn.get("models") do |req|
        req.headers["Authorization"] = "Bearer #{key}"
        req.headers["Content-Type"]  = "application/json"
      end

      if res.success?
        body   = JSON.parse(res.body)
        data   = body["data"]
        models = data.is_a?(Array) ? data.map { |m| m["id"] }.compact.first(5) : []
        render json: { ok: true, models: models, total: data&.size || 0 }
      else
        body_preview = res.body.to_s.first(200)
        render json: { error: "Erreur API #{res.status} — #{body_preview}" }
      end
    rescue JSON::ParserError => e
      render json: { error: "Réponse invalide (non-JSON) : #{e.message}" }
    rescue Faraday::TimeoutError
      render json: { error: "Timeout — OpenRouter ne répond pas (> 15s)" }
    rescue Faraday::ConnectionFailed => e
      render json: { error: "Connexion impossible : #{e.message}" }
    rescue => e
      render json: { error: "#{e.class} — #{e.message}" }
    end

    # GET /admin/configs/test_stripe
    def test_stripe
      key = AppConfig.get("stripe_secret_key")
      return render json: { error: "Clé Stripe manquante — configurez stripe_secret_key" }, status: :bad_request if key.blank?

      Stripe.api_key = key
      balance = Stripe::Balance.retrieve
      render json: {
        ok:       true,
        livemode: balance.livemode,
        mode:     balance.livemode ? "🔴 Production (live)" : "🟡 Test mode",
        available: balance.available.map { |b| "#{b.amount / 100.0} #{b.currency.upcase}" }.join(", ")
      }
    rescue Stripe::AuthenticationError
      render json: { error: "Clé Stripe invalide ou révoquée" }
    rescue Stripe::StripeError => e
      render json: { error: "Stripe error: #{e.message}" }
    rescue => e
      render json: { error: "#{e.class}: #{e.message}" }
    end

    # GET /admin/configs/test_resend
    def test_resend
      key = AppConfig.get("resend_api_key") || ENV["RESEND_API_KEY"]
      return render json: { error: "Clé Resend manquante — vérifiez RESEND_API_KEY dans .env" }, status: :bad_request if key.blank?

      conn = Faraday.new(url: "https://api.resend.com/") do |f|
        f.options.timeout      = 10
        f.options.open_timeout = 8
        f.adapter Faraday.default_adapter
      end

      res = conn.get("domains") do |req|
        req.headers["Authorization"] = "Bearer #{key}"
        req.headers["Content-Type"]  = "application/json"
      end

      if res.success?
        body    = JSON.parse(res.body)
        domains = Array(body["data"]).map { |d| "#{d["name"]} (#{d["status"]})" }.join(", ")
        render json: { ok: true, domains: domains.presence || "aucun domaine configuré" }
      elsif res.status == 401
        render json: { error: "Clé Resend invalide ou révoquée (401)" }
      else
        render json: { error: "Resend API #{res.status} — #{res.body.first(200)}" }
      end
    rescue Faraday::TimeoutError
      render json: { error: "Timeout — Resend ne répond pas" }
    rescue => e
      render json: { error: "#{e.class}: #{e.message}" }
    end

    # GET /admin/configs/test_api
    def test_api
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      conn = Faraday.new(url: "https://api.diet-vision.com/") do |f|
        f.options.timeout      = 10
        f.options.open_timeout = 8
        f.adapter Faraday.default_adapter
      end

      results = {}

      # Test 1 — Health
      begin
        r = conn.get("api/v1/health")
        results[:health] = r.success? ? { ok: true, status: r.status } : { ok: false, status: r.status }
      rescue => e
        results[:health] = { ok: false, error: e.message }
      end

      # Test 2 — Plans (public)
      begin
        r = conn.get("api/v1/plans")
        if r.success?
          plans = JSON.parse(r.body)
          results[:plans] = { ok: true, count: plans.size }
        else
          results[:plans] = { ok: false, status: r.status }
        end
      rescue => e
        results[:plans] = { ok: false, error: e.message }
      end

      # Test 3 — RGPD (public)
      begin
        r = conn.get("api/v1/legal/rgpd")
        results[:rgpd] = r.success? ? { ok: true, status: r.status } : { ok: false, status: r.status }
      rescue => e
        results[:rgpd] = { ok: false, error: e.message }
      end

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      all_ok = results.values.all? { |r| r[:ok] }

      render json: { ok: all_ok, duration_ms: duration_ms, endpoints: results }
    rescue => e
      render json: { error: "#{e.class}: #{e.message}" }
    end

    private

    def description_for(key)
      {
        "openrouter_api_key"       => "Clé API OpenRouter (sk-or-v1-...)",
        "openrouter_default_model" => "Modèle texte par défaut (ex: google/gemini-2.0-flash-001)",
        "openrouter_vision_model"  => "Modèle vision pour analyse photo",
        "free_plan_daily_limit"    => "Nb d'appels IA/jour — plan gratuit",
        "premium_plan_daily_limit" => "Nb d'appels IA/jour — plan premium",
        "trial_enabled"            => "Activer la période d'essai pour les nouveaux inscrits (1 = oui, 0 = non)",
        "trial_period_days"        => "Durée de la période d'essai (en jours)",
        "app_name"                 => "Nom de l'application",
        "support_email"            => "Email support affiché dans les emails",
        "report_sender_email"      => "Email expéditeur des rapports (ex: rapports@diet-vision.com)",
        "stripe_publishable_key"   => "Stripe — Publishable key (pk_live_... ou pk_test_...)",
        "stripe_secret_key"        => "Stripe — Secret key (sk_live_... ou sk_test_...)",
        "stripe_webhook_secret"    => "Stripe — Webhook signing secret (whsec_...)",
        "email_app_url"            => "URL principale de l'app dans les emails (bouton CTA)",
        "email_scan_deeplink"      => "Deep link bouton « Scanner un repas » (ex: dietvision://scan)",
        "email_measures_deeplink"  => "Deep link bouton « Ajouter mes mesures » (ex: dietvision://measures)",
        "email_coach_deeplink"     => "Deep link bouton « Coach IA » (ex: dietvision://coach)",
        "email_report_tip_fr"      => "Conseil affiché dans le rapport — version française",
        "email_report_tip_en"      => "Conseil affiché dans le rapport — version anglaise (us/en)",
        "email_report_tip_de"      => "Conseil affiché dans le rapport — version allemande",
        "email_report_tip_es"      => "Conseil affiché dans le rapport — version espagnole",
      }[key]
    end
  end
end
