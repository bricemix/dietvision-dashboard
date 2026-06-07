class AppConfig < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Clés gérées
  KEYS = %w[
    openrouter_api_key
    openrouter_default_model
    openrouter_vision_model
    free_scan_daily_limit
    free_chat_daily_limit
    starter_scan_daily_limit
    starter_chat_daily_limit
    trial_scan_daily_limit
    trial_chat_daily_limit
    pro_plan_daily_limit
    premium_plan_daily_limit
    vip_plan_daily_limit
    pro_dishes_daily_limit
    premium_dishes_daily_limit
    vip_dishes_daily_limit
    trial_enabled
    trial_period_days
    app_name
    support_email
    report_sender_email
    stripe_mode
    stripe_publishable_key
    stripe_secret_key
    stripe_webhook_secret
    stripe_publishable_key_test
    stripe_secret_key_test
    stripe_webhook_secret_test
    email_app_url
    email_scan_deeplink
    email_measures_deeplink
    email_coach_deeplink
    email_report_tip_fr
    email_report_tip_en
    email_report_tip_de
    email_report_tip_es
  ].freeze

  # BUG-12 : cache pour éviter 2-4 requêtes SQL par request API
  # BUG-06 : les clés sensibles ne sont jamais loggées (ActiveRecord::Base.logger)
  CACHE_TTL     = 5.minutes
  SENSITIVE_KEYS = %w[stripe_secret_key stripe_webhook_secret stripe_secret_key_test stripe_webhook_secret_test openrouter_api_key].freeze

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
  def self.default_model           = get("openrouter_default_model") || "google/gemini-2.5-flash"
  def self.vision_model            = get("openrouter_vision_model") || "google/gemini-2.5-flash"
  # Limites scan (analyze_food) par plan
  def self.free_scan_daily_limit     = get("free_scan_daily_limit")&.to_i    || 3
  def self.starter_scan_daily_limit  = get("starter_scan_daily_limit")&.to_i || 20
  def self.trial_scan_daily_limit    = get("trial_scan_daily_limit")&.to_i   || 10
  # Limites chat (coach_chat) par plan — 999 = illimité
  def self.free_chat_daily_limit     = get("free_chat_daily_limit")&.to_i    || 5
  def self.starter_chat_daily_limit  = get("starter_chat_daily_limit")&.to_i || 999
  def self.trial_chat_daily_limit    = get("trial_chat_daily_limit")&.to_i   || 10
  # Pro : 50 scans / 100 chats par jour
  def self.pro_scan_daily_limit     = get("pro_scan_daily_limit")&.to_i     || 50
  def self.pro_chat_daily_limit     = get("pro_chat_daily_limit")&.to_i     || 100
  # Premium : 150 scans / 200 chats par jour
  def self.premium_scan_daily_limit = get("premium_scan_daily_limit")&.to_i || 150
  def self.premium_chat_daily_limit = get("premium_chat_daily_limit")&.to_i || 200
  # VIP : illimité (999)
  def self.vip_daily_limit         = get("vip_plan_daily_limit")&.to_i || 999
  # Limites journalières — Plats recommandés (nombre de rafraîchissements)
  # Free/Trial : 0 (feature verrouillée côté Flutter + backend)
  def self.pro_dishes_limit        = get("pro_dishes_daily_limit")&.to_i || 50
  def self.premium_dishes_limit    = get("premium_dishes_daily_limit")&.to_i || 150
  def self.vip_dishes_limit        = get("vip_dishes_daily_limit")&.to_i || 999
  # Essai activé par défaut (opt-out) — désactiver explicitement avec "0" ou "false"
  def self.trial_enabled?
    val = get("trial_enabled")
    return true if val.nil?                        # non configuré → actif par défaut
    val.to_s.in?(%w[1 true yes])
  end
  # 0 si non configuré — doit être défini dans le dashboard pour activer l'essai
  def self.trial_period_days       = get("trial_period_days")&.to_i || 0
  # Retourne "live" ou "test" (live par défaut)
  def self.stripe_mode = get("stripe_mode").presence&.in?(%w[live test]) ? get("stripe_mode") : "live"
  def self.stripe_live_mode? = stripe_mode == "live"
  def self.stripe_test_mode? = stripe_mode == "test"

  # Accesseurs contextuels : retourne la clé du mode actif
  def self.stripe_publishable_key
    stripe_test_mode? ? (get("stripe_publishable_key_test") || ENV["STRIPE_PUBLISHABLE_KEY_TEST"]) :
                        (get("stripe_publishable_key")      || ENV["STRIPE_PUBLISHABLE_KEY"])
  end
  def self.stripe_secret_key
    stripe_test_mode? ? (get("stripe_secret_key_test") || ENV["STRIPE_SECRET_KEY_TEST"]) :
                        (get("stripe_secret_key")       || ENV["STRIPE_SECRET_KEY"])
  end
  def self.stripe_webhook_secret
    stripe_test_mode? ? (get("stripe_webhook_secret_test") || ENV["STRIPE_WEBHOOK_SECRET_TEST"]) :
                        (get("stripe_webhook_secret")       || ENV["STRIPE_WEBHOOK_SECRET"])
  end
end
