class Subscription < ApplicationRecord
  belongs_to :user
  has_many   :payments, dependent: :nullify

  validates :plan,   presence: true
  validates :status, inclusion: { in: %w[pending active expired cancelled] }

  scope :active,   -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :expired,  -> { where("expires_at < ?", Time.current).or(where(status: "expired")) }

  # Active l'abonnement en se basant sur le Plan modèle (Stripe)
  def activate!(duration: nil)
    plan_obj  = Plan.find_by(slug: plan)
    duration  ||= plan_obj&.duration || 1.month

    update!(
      status:     "active",
      starts_at:  Time.current,
      expires_at: Time.current + duration
    )
    user.update!(
      plan: "premium",
      subscription_expires_at: expires_at
    )
  end

  def label
    Plan.find_by(slug: plan)&.name || plan.capitalize
  end
end
