module JwtAuthenticatable
  extend ActiveSupport::Concern

  SECRET_KEY = Rails.application.secret_key_base
  ALGORITHM  = "HS256"
  TTL        = 30.days

  included do
    before_action :authenticate_user!
  end

  module ClassMethods
    def skip_authentication(*actions)
      skip_before_action :authenticate_user!, only: actions
    end
  end

  # ---- Token generation ----

  def self.encode(payload)
    payload = payload.merge(exp: TTL.from_now.to_i, iat: Time.current.to_i)
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY, true, algorithm: ALGORITHM)
    HashWithIndifferentAccess.new(decoded.first)
  rescue JWT::ExpiredSignature
    raise "Token expiré"
  rescue JWT::DecodeError => e
    raise "Token invalide: #{e.message}"
  end

  # ---- Controller helpers ----

  def authenticate_user!
    token = extract_token
    return render_unauthorized("Token manquant") unless token

    payload = JwtAuthenticatable.decode(token)
    @current_user = User.find_by(id: payload[:user_id])

    return render_unauthorized("Utilisateur introuvable") unless @current_user
    return render_unauthorized("Compte suspendu")         if @current_user.status == "suspended"

    # ── Session unique : un seul appareil à la fois ───────────────────────────
    # Si l'utilisateur s'est reconnecté sur un autre appareil, session_token
    # aura changé en base → l'ancien token JWT devient invalide.
    if @current_user.session_token.present? &&
        payload[:session_token] != @current_user.session_token
      return render json: {
        error: "Votre compte a été connecté sur un autre appareil.",
        code:  "SESSION_INVALIDATED"
      }, status: :unauthorized
    end
  rescue => e
    render_unauthorized(e.message)
  end

  def current_user
    @current_user
  end

  private

  def extract_token
    header = request.headers["Authorization"]
    header&.split(" ")&.last
  end

  def render_unauthorized(message = "Non autorisé")
    render json: { error: message }, status: :unauthorized
  end
end
