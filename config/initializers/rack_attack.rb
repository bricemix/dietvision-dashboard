class Rack::Attack
  # ── Whitelist : endpoint webhook Stripe ──────────────────────────────────────
  # Les webhooks Stripe ne portent pas de JWT et peuvent être envoyés en rafale
  # (replay des événements manqués). On les exclut de tout throttle pour éviter
  # qu'un 429 fasse croire à Stripe que l'endpoint est en panne.
  # La sécurité est assurée par la vérification de signature HMAC dans le contrôleur.
  safelist("allow-stripe-webhook") do |req|
    req.path == "/api/v1/payments/webhook" && req.post?
  end

  # ── Throttle : login API mobile (brute-force credentials) ────────────────────
  # 10 tentatives par IP sur 1 minute
  throttle("api/login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/auth/login" && req.post?
  end

  # 5 tentatives par email sur 5 minutes (credential stuffing)
  throttle("api/login/email", limit: 5, period: 5.minutes) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      begin
        body = JSON.parse(req.body.read)
        req.body.rewind
        body["email"].to_s.downcase.strip.presence
      rescue
        nil
      end
    end
  end

  # ── Throttle : vérification email (brute-force code OTP) ─────────────────────
  # 10 tentatives par IP sur 5 minutes
  throttle("api/verify_email/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.path == "/api/v1/auth/verify_email" && req.post?
  end

  # ── Throttle : reset mot de passe (brute-force token) ────────────────────────
  throttle("api/reset_password/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.path == "/api/v1/auth/reset_password" && req.post?
  end

  # ── Throttle : envoi de code (spam) ──────────────────────────────────────────
  throttle("api/send_verification/ip", limit: 5, period: 10.minutes) do |req|
    req.ip if req.path == "/api/v1/auth/send_verification" && req.post?
  end

  throttle("api/forgot_password/ip", limit: 5, period: 10.minutes) do |req|
    req.ip if req.path == "/api/v1/auth/forgot_password" && req.post?
  end

  # Throttle : inscription (spam de comptes) — 5 par IP / 10 min
  throttle("api/register/ip", limit: 5, period: 10.minutes) do |req|
    req.ip if req.path == "/api/v1/auth/register" && req.post?
  end

  # ── Throttle : login admin (BUG-07) ──────────────────────────────────────────
  # 5 tentatives par IP sur 5 minutes sur le login admin
  throttle("admin/login/ip", limit: 5, period: 5.minutes) do |req|
    req.ip if req.path == "/admin/login" && req.post?
  end

  # ── Throttle général API : éviter les abus ───────────────────────────────────
  throttle("api/general/ip", limit: 300, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # ── Réponse en cas de blocage ─────────────────────────────────────────────────
  self.throttled_responder = lambda do |env|
    match_data = env["rack.attack.match_data"]
    now        = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    [
      429,
      {
        "Content-Type"  => "application/json",
        "Retry-After"   => retry_after.to_s
      },
      [ { error: "Too many requests. Please try again later.",
          retry_after: retry_after }.to_json ]
    ]
  end
end
