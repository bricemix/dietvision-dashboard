class UserMailer < ApplicationMailer
  # E-mail de bienvenue envoyé après inscription
  def welcome(user)
    @user = user
    mail(
      to:      "#{user.name} <#{user.email}>",
      subject: "Bienvenue sur DietVision 🥗"
    )
  end

  # Échec de paiement (renouvellement) — envoyé par invoice.payment_failed
  def payment_failed(user)
    @user = user
    mail(
      to:      "#{user.name} <#{user.email}>",
      subject: "⚠️ Problème de paiement — DietVision Premium"
    )
  end

  # Confirmation d'activation Premium — envoyé par invoice.paid (optionnel)
  def subscription_activated(user, expires_at)
    @user       = user
    @expires_at = expires_at
    mail(
      to:      "#{user.name} <#{user.email}>",
      subject: "✅ Votre abonnement Premium est actif — DietVision"
    )
  end
end
