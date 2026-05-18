class User < ApplicationRecord
  has_secure_password

  has_many :subscriptions, dependent: :destroy
  has_many :payments,      dependent: :destroy
  has_many :api_usages,    dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name,  presence: true
  validates :phone, presence: false   # facultatif (app mobile)

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
end
