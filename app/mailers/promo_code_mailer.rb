class PromoCodeMailer < ApplicationMailer
  # Résumé quotidien envoyé aux emails configurés sur un code promo.
  def daily_usage_report(promo_code:, emails:, today_count:, today_unique:, total_uses:, total_unique:)
    @promo_code   = promo_code
    @today_count  = today_count
    @today_unique = today_unique
    @total_uses   = total_uses
    @total_unique = total_unique
    @date         = Date.current

    mail(
      to:      emails,
      subject: "📊 Code #{promo_code.code} — #{today_unique} utilisateur#{today_unique > 1 ? 's' : ''} aujourd'hui"
    )
  end
end
