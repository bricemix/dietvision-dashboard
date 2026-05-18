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

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
  end

  def self.openrouter_api_key      = get("openrouter_api_key")
  def self.default_model           = get("openrouter_default_model") || "google/gemini-2.0-flash-001"
  def self.vision_model            = get("openrouter_vision_model") || "google/gemini-2.0-flash-001"
  def self.free_daily_limit        = get("free_plan_daily_limit")&.to_i || 5
  def self.premium_daily_limit     = get("premium_plan_daily_limit")&.to_i || 100
  def self.trial_enabled?          = get("trial_enabled").to_s.in?(%w[1 true yes])
  def self.trial_period_days       = get("trial_period_days")&.to_i || 0
  def self.stripe_publishable_key  = get("stripe_publishable_key") || ENV["STRIPE_PUBLISHABLE_KEY"]
  def self.stripe_secret_key       = get("stripe_secret_key")      || ENV["STRIPE_SECRET_KEY"]
  def self.stripe_webhook_secret   = get("stripe_webhook_secret")  || ENV["STRIPE_WEBHOOK_SECRET"]
end
