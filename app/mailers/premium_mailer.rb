class PremiumMailer < ApplicationMailer
  # Bilan hebdomadaire envoyé chaque lundi aux utilisateurs premium
  def weekly_digest(user)
    @user = user

    # Stats de la semaine écoulée (lun → dim)
    week_start = 1.week.ago.beginning_of_day
    week_end   = Time.current

    usages = user.api_usages.where(created_at: week_start..week_end)

    @analyses_count = usages.where(endpoint: "analyze_food").count
    @coach_count    = usages.where(endpoint: "coach_chat").count
    @total_calls    = usages.count

    # Stats du mois pour contexte
    @analyses_month = user.api_usages
                          .where(endpoint: "analyze_food",
                                 created_at: Time.current.beginning_of_month..)
                          .count

    # Infos abonnement
    @expires_at      = user.subscription_expires_at
    @days_remaining  = @expires_at ? ((@expires_at - Time.current) / 1.day).ceil : nil
    @expiry_warning  = @days_remaining && @days_remaining <= 7 && @days_remaining > 0

    # Semaine formatée
    @week_label = "#{1.week.ago.strftime("%-d %b")} – #{Date.current.strftime("%-d %b %Y")}"

    # Niveau d'activité
    @activity_level = case @analyses_count
    when 0     then "inactive"
    when 1..3  then "low"
    when 4..10 then "medium"
    else            "high"
    end

    mail(
      to:      "#{user.name} <#{user.email}>",
      subject: "Votre bilan DietVision — semaine du #{1.week.ago.strftime("%-d %b")}"
    )
  end
end
