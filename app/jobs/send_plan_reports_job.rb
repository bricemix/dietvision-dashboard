# Envoie les rapports nutritionnels automatiques aux utilisateurs abonnés,
# selon la fréquence configurée sur chaque plan.
#
# Doit être planifié via un scheduler (cron, Sidekiq-cron, Whenever, etc.)
# pour s'exécuter chaque matin (ex : 08h00 UTC).
#
# Exemple avec Whenever (config/schedule.rb) :
#   every 1.day, at: '8:00 am' do
#     runner "SendPlanReportsJob.perform_now"
#   end
#
# Exemple avec Sidekiq-cron (config/initializers/sidekiq.rb) :
#   Sidekiq::Cron::Job.create(
#     name: 'Daily plan reports',
#     cron: '0 8 * * *',
#     class: 'SendPlanReportsJob'
#   )
class SendPlanReportsJob < ApplicationJob
  queue_as :mailers

  def perform
    today = Date.current

    Plan.where.not(email_report_frequency: [ "never", nil ]).each do |plan|
      next unless should_send_today?(plan, today)

      # Tous les utilisateurs actifs sur ce plan (vérification abonnement si nécessaire)
      users = eligible_users_for_plan(plan)

      Rails.logger.info "[SendPlanReportsJob] Plan '#{plan.name}' (#{plan.email_report_frequency}) → #{users.count} destinataire(s)"

      users.each do |user|
        begin
          ReportMailer.nutrition_report(user, plan).deliver_later
        rescue => e
          Rails.logger.error "[SendPlanReportsJob] Erreur pour user #{user.id} (#{user.email}): #{e.message}"
        end
      end
    end
  end

  private

  # Vérifie si le plan doit être envoyé aujourd'hui selon sa fréquence.
  def should_send_today?(plan, today)
    case plan.email_report_frequency
    when "daily"
      true  # toujours
    when "weekly"
      day_map = {
        "monday"    => 1, "tuesday"  => 2, "wednesday" => 3, "thursday" => 4,
        "friday"    => 5, "saturday" => 6, "sunday"    => 7
      }
      configured_day = day_map[plan.email_report_day.to_s.downcase] || 1
      today.cwday == configured_day
    when "monthly"
      today.day == 1  # premier du mois
    else
      false
    end
  end

  # Retourne les utilisateurs éligibles pour ce plan (actifs + abonnement valide si premium).
  def eligible_users_for_plan(plan)
    users = User.where(plan: plan.slug, status: "active")

    # Pour les plans payants, on vérifie aussi que l'abonnement n'est pas expiré
    if plan.price_eur_cents.to_i > 0
      users = users.where(
        "subscription_expires_at IS NULL OR subscription_expires_at > ?", Time.current
      )
    end

    users
  end
end
