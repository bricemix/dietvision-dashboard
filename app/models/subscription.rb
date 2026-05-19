class Subscription < ApplicationRecord
  belongs_to :user
  has_many   :payments, dependent: :nullify

  validates :plan,   presence: true
  # BUG-09 FIXÉ : past_due ajouté — handle_invoice_payment_failed en avait besoin
  validates :status, inclusion: { in: %w[pending active expired cancelled past_due] }

  scope :active,   -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :expired,  -> { where("expires_at < ?", Time.current).or(where(status: "expired")) }

  # DÉPRÉCIÉ pour les paiements Stripe : expires_at doit venir de Stripe (current_period_end),
  # pas être calculé localement. Utiliser StripeService#handle_invoice_paid à la place.
  # Conservé uniquement pour les paiements mobile money (CinetPay, Wave, MTN, Orange).
  def activate!(duration: nil)
    Rails.logger.warn("[Subscription#activate!] Appelé sans date Stripe — expires_at calculé localement. " \
                      "Utiliser StripeService#handle_invoice_paid pour les paiements Stripe.") if stripe_subscription_id.present?

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
