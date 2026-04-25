class AppConfig < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Clés gérées
  KEYS = %w[
    openrouter_api_key
    openrouter_default_model
    openrouter_vision_model
    free_plan_daily_limit
    premium_plan_daily_limit
    cinetpay_api_key
    cinetpay_site_id
    app_name
    support_email
  ].freeze

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
  end

  def self.openrouter_api_key   = get("openrouter_api_key")
  def self.default_model        = get("openrouter_default_model") || "google/gemini-2.0-flash-001"
  def self.vision_model         = get("openrouter_vision_model") || "google/gemini-2.0-flash-001"
  def self.free_daily_limit     = get("free_plan_daily_limit")&.to_i || 5
  def self.premium_daily_limit  = get("premium_plan_daily_limit")&.to_i || 100
  def self.cinetpay_api_key     = get("cinetpay_api_key")
  def self.cinetpay_site_id     = get("cinetpay_site_id")
end
