class UserMailer < ApplicationMailer
  # E-mail de bienvenue envoyé après inscription (traduit selon user.locale)
  def welcome(user)
    @user = user
    locale = user.locale.presence&.to_sym || :fr
    locale = :fr unless %i[fr en de es].include?(locale)
    I18n.with_locale(locale) do
      mail(
        to:      "#{user.name} <#{user.email}>",
        subject: I18n.t("user_mailer.welcome.subject", app: "DietVision")
      )
    end
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

  # Confirmation d'activation abonnement — envoyé par invoice.paid
  # plan_level : 'starter' | 'pro' | 'premium'
  def subscription_activated(user, expires_at, plan_level: nil)
    @user       = user
    @expires_at = expires_at
    @plan_level = (plan_level || user.plan || "premium").to_s.downcase
    @plan_name  = case @plan_level
                  when "premium" then "Premium"
                  when "pro"     then "Pro"
                  when "starter" then "Starter"
                  else @plan_level.capitalize
                  end
    mail(
      to:      "#{user.name} <#{user.email}>",
      subject: "✅ Votre abonnement #{@plan_name} est actif — DietVision"
    )
  end
end
