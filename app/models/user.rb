class User < ApplicationRecord
  has_secure_password

  has_many :subscriptions, dependent: :destroy
  has_many :payments,      dependent: :destroy
  has_many :api_usages,    dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name,  presence: true
  validates :phone, presence: false   # facultatif (app mobile)
  validate  :password_complexity, if: -> { password.present? }

  PASSWORD_REGEX = /\A(?=.*[A-Z])(?=.*[\d!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]).{8,}\z/

  def password_complexity
    return if password.blank?
    unless password.length >= 8
      errors.add(:password, "doit contenir au moins 8 caractères")
      return
    end
    unless password.match?(/[A-Z]/)
      errors.add(:password, "doit contenir au moins une lettre majuscule")
    end
    unless password.match?(/[\d!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/)
      errors.add(:password, "doit contenir au moins un chiffre ou caractère spécial")
    end
  end

  before_save { self.email = email.downcase }

  # ── Scopes ────────────────────────────────────────────────────

  scope :in_trial,       -> { where("trial_ends_at > ?", Time.current) }
  scope :trial_expired,  -> { where("trial_ends_at IS NOT NULL AND trial_ends_at < ?", Time.current) }
  scope :active_users,   -> { where(status: "active") }
  scope :new_this_month, -> { where(created_at: Time.current.beginning_of_month..) }

  # ── Subscription helpers ──────────────────────────────────────

  def premium?
    plan == "premium" && subscription_expires_at&.future?
  end

  def in_trial?
    trial_ends_at.present? && trial_ends_at.future?
  end

  def trial_days_remaining
    return 0 unless in_trial?
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  def start_trial!(days)
    update!(
      trial_ends_at: Time.current + days.days,
      had_trial: true,
      plan: "free"
    )
  end

  def active_subscription
    subscriptions.where(status: "active").order(expires_at: :desc).first
  end

  def total_spent
    payments.where(status: "success").sum(:amount)
  end

  def api_calls_this_month
    api_usages.where(created_at: Time.current.beginning_of_month..).count
  end

  # ── Email verification ────────────────────────────────────────

  def email_verified?
    email_verified_at.present?
  end

  # Génère un code à 6 chiffres, le sauvegarde, retourne le code
  def generate_verification_code!
    code = rand(100_000..999_999).to_s
    update!(
      email_verification_code:    code,
      email_verification_sent_at: Time.current
    )
    code
  end

  # Vérifie le code saisi — true si valide (code correct + < 15 min)
  def verify_email!(code)
    return false if email_verification_code.blank?
    return false if email_verification_sent_at.nil? || email_verification_sent_at < 15.minutes.ago
    return false if email_verification_code != code.to_s.strip
    update!(
      email_verified_at:          Time.current,
      email_verification_code:    nil,
      email_verification_sent_at: nil
    )
    true
  end

  def verification_code_cooldown?
    email_verification_sent_at.present? && email_verification_sent_at > 60.seconds.ago
  end

  # ── Password reset ────────────────────────────────────────────

  # Génère un code à 6 chiffres valable 1h, le sauvegarde et le retourne
  def generate_password_reset_token!
    token = rand(100_000..999_999).to_s
    update_columns(
      password_reset_token:   token,
      password_reset_sent_at: Time.current
    )
    token
  end

  # Réinitialise le mot de passe si le code est valide (< 1h)
  # Retourne true si succès, false sinon
  def reset_password_with_token!(token, new_password)
    return false if password_reset_token.blank?
    return false if password_reset_sent_at.nil? || password_reset_sent_at < 1.hour.ago
    return false if password_reset_token != token.to_s.strip
    self.password = new_password
    if save
      update_columns(password_reset_token: nil, password_reset_sent_at: nil)
      true
    else
      false
    end
  end

  def password_reset_cooldown?
    password_reset_sent_at.present? && password_reset_sent_at > 60.seconds.ago
  end
end
