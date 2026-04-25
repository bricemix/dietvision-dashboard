class Subscription < ApplicationRecord
  belongs_to :user
  has_many   :payments, dependent: :nullify

  PLANS = {
    "monthly" => { price: 2000, duration: 1.month,  label: "Mensuel" },
    "yearly"  => { price: 18000, duration: 1.year,  label: "Annuel"  }
  }.freeze

  validates :plan,   inclusion: { in: PLANS.keys }
  validates :status, inclusion: { in: %w[pending active expired cancelled] }

  scope :active,   -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :expired,  -> { where("expires_at < ?", Time.current).or(where(status: "expired")) }

  def activate!
    plan_config = PLANS[plan]
    update!(
      status:     "active",
      starts_at:  Time.current,
      expires_at: Time.current + plan_config[:duration]
    )
    user.update!(
      plan: "premium",
      subscription_expires_at: expires_at
    )
  end

  def label
    PLANS.dig(plan, :label) || plan
  end
end
