class AppConfig < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Clés gérées
  KEYS = %w[
    openrouter_api_key
    openrouter_default_model
    openrouter_vision_model
    free_plan_daily_limit
    premium_plan_daily_limit
    trial_enabled
    trial_period_days
    app_name
    support_email
    stripe_publishable_key
    stripe_secret_key
    stripe_webhook_secret
  ].freeze

  # BUG-12 : cache pour éviter 2-4 requêtes SQL par request API
  # BUG-06 : les clés sensibles ne sont jamais loggées (ActiveRecord::Base.logger)
  CACHE_TTL     = 5.minutes
  SENSITIVE_KEYS = %w[stripe_secret_key stripe_webhook_secret openrouter_api_key].freeze

  def self.get(key)
    Rails.cache.fetch("app_config/#{key}", expires_in: CACHE_TTL) do
      find_by(key: key)&.value
    end
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    Rails.cache.delete("app_config/#{key}")
  end

  # Retourne la valeur masquée pour l'affichage (12 premiers chars + *** + 4 derniers)
  def self.masked(key)
    val = get(key)
    return nil if val.blank?
    val.length > 20 ? "#{val[0..11]}••••••••#{val[-4..]}" : "#{val[0..3]}••••••"
  end

  def self.openrouter_api_key      = get("openrouter_api_key")
  def self.default_model           = get("openrouter_default_model") || "google/gemini-2.0-flash-001"
  def self.vision_model            = get("openrouter_vision_model") || "google/gemini-2.0-flash-001"
  def self.free_daily_limit        = get("free_plan_daily_limit")&.to_i || 5
  def self.premium_daily_limit     = get("premium_plan_daily_limit")&.to_i || 100
  # Essai activé par défaut (opt-out) — désactiver explicitement avec "0" ou "false"
  def self.trial_enabled?
    val = get("trial_enabled")
    return true if val.nil?                        # non configuré → actif par défaut
    val.to_s.in?(%w[1 true yes])
  end
  # 0 si non configuré — doit être défini dans le dashboard pour activer l'essai
  def self.trial_period_days       = get("trial_period_days")&.to_i || 0
  def self.stripe_publishable_key  = get("stripe_publishable_key") || ENV["STRIPE_PUBLISHABLE_KEY"]
  def self.stripe_secret_key       = get("stripe_secret_key")      || ENV["STRIPE_SECRET_KEY"]
  def self.stripe_webhook_secret   = get("stripe_webhook_secret")  || ENV["STRIPE_WEBHOOK_SECRET"]
end
