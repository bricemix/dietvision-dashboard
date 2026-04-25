class User < ApplicationRecord
  has_secure_password

  has_many :subscriptions, dependent: :destroy
  has_many :payments,      dependent: :destroy
  has_many :api_usages,    dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name,  presence: true
  validates :phone, presence: true

  before_save { self.email = email.downcase }

  # Subscription helpers
  def premium?
    plan == "premium" && subscription_expires_at&.future?
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
