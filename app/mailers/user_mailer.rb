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

  # Code de vérification d'adresse e-mail
  def verification_code(user, code)
    @user = user
    @code = code
    mail(
      to:      "#{user.name} <#{user.email}>",
      subject: "#{code} — Votre code de vérification DietVision"
    )
  end

  # Code de réinitialisation de mot de passe (code 6 chiffres, valable 3 min)
  def password_reset(user, token)
    @user  = user
    @token = token
    mail(
      to:      "#{user.name} <#{user.email}>",
      subject: "#{token} est votre code DietVision"
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
