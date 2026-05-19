class AdminUser < ApplicationRecord
  has_secure_password

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  before_save { self.email = email.downcase }

  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_DURATION    = 15.minutes

  def superadmin?
    role == "superadmin"
  end

  # ── Brute-force protection ─────────────────────────────────────────────────

  def locked?
    locked_until.present? && locked_until.future?
  end

  def record_failed_login!
    new_count = (failed_login_count || 0) + 1
    attrs = { failed_login_count: new_count }
    attrs[:locked_until] = Time.current + LOCKOUT_DURATION if new_count >= MAX_FAILED_ATTEMPTS
    update_columns(attrs)
  end

  def record_successful_login!
    update_columns(failed_login_count: 0, locked_until: nil, last_login_at: Time.current)
  end
end
