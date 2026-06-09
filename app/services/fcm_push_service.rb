# Envoi de notifications push via l'API Firebase Cloud Messaging HTTP v1.
# OAuth2 fait à la main (gem jwt déjà présente) → pas de dépendance googleauth.
require "jwt"
require "json"
require "openssl"
require "uri"

class FcmPushService
  SCOPE     = "https://www.googleapis.com/auth/firebase.messaging".freeze
  TOKEN_URI = "https://oauth2.googleapis.com/token".freeze

  class ConfigError < StandardError; end

  def initialize(key_path: nil)
    path = key_path ||
           ENV["FCM_SERVICE_ACCOUNT"].presence ||
           Rails.root.join("config", "fcm-service-account.json").to_s
    raise ConfigError, "Clé de service FCM introuvable (#{path})" unless File.exist?(path)
    @creds      = JSON.parse(File.read(path))
    @project_id = @creds["project_id"]
  end

  # Envoi à plusieurs tokens. Retourne un récap + la liste des tokens invalides.
  def send_to_tokens(tokens, title:, body:, data: {})
    access  = access_token
    result  = { sent: 0, failed: 0, invalid: [] }
    Array(tokens).uniq.each do |tok|
      resp = post_message(access, tok, title, body, data)
      if resp.status.to_i == 200
        result[:sent] += 1
      else
        result[:failed] += 1
        # 400 INVALID_ARGUMENT / 404 UNREGISTERED → token mort à purger
        result[:invalid] << tok if [400, 404].include?(resp.status.to_i)
        Rails.logger.warn("[FCM] échec token #{tok[0, 12]}… status=#{resp.status} #{resp.body.to_s[0, 200]}")
      end
    end
    result
  end

  # Valide les credentials : retourne true si on obtient un access_token.
  def credentials_ok?
    access_token.present?
  rescue => e
    Rails.logger.error("[FCM] credentials_ok? error: #{e.message}")
    false
  end

  private

  def conn
    @conn ||= Faraday.new { |f| f.options.timeout = 20; f.adapter Faraday.default_adapter }
  end

  def post_message(access, token, title, body, data)
    payload = {
      message: {
        token: token,
        notification: { title: title, body: body },
        data: (data || {}).transform_values(&:to_s),
        android: { priority: "high", notification: { sound: "default" } },
        apns: { payload: { aps: { sound: "default" } } }
      }
    }
    conn.post("https://fcm.googleapis.com/v1/projects/#{@project_id}/messages:send") do |req|
      req.headers["Authorization"] = "Bearer #{access}"
      req.headers["Content-Type"]  = "application/json"
      req.body = payload.to_json
    end
  end

  # Mémoïsé pour toute la durée de vie de l'instance (token valide 1h) →
  # permet d'envoyer à des milliers d'utilisateurs sans ré-authentifier.
  def access_token
    @access_token ||= fetch_access_token
  end

  def fetch_access_token
    now = Time.now.to_i
    assertion = JWT.encode(
      { iss: @creds["client_email"], scope: SCOPE, aud: TOKEN_URI, iat: now, exp: now + 3600 },
      OpenSSL::PKey::RSA.new(@creds["private_key"]),
      "RS256"
    )
    resp = conn.post(TOKEN_URI) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion:  assertion
      )
    end
    JSON.parse(resp.body)["access_token"]
  end
end
