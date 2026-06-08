# Envoie les rapports nutritionnels automatiques selon le palier de plan.
#
# Pro     : mensuel
# Premium : hebdomadaire
# VIP     : quotidien + hebdomadaire + mensuel
#
# Planifié via cron (chaque matin) :
#   0 7 * * *  bundle exec rails runner "SendPlanReportsJob.perform_now"
# Le job décide lui-même quels rapports envoyer selon la date du jour.
class SendPlanReportsJob < ApplicationJob
  queue_as :mailers

  # Fréquences de rapport par palier (slug de base du plan)
  TIER_FREQUENCIES = {
    "pro"     => %w[monthly],
    "premium" => %w[weekly],
    "vip"     => %w[daily weekly monthly]
  }.freeze

  def perform
    today = Date.current

    TIER_FREQUENCIES.each do |tier, frequencies|
      plan = Plan.find_by(slug: tier)
      next unless plan

      due = frequencies.select { |f| should_send_today?(f, today) }
      next if due.empty?

      users = eligible_users_for_tier(tier)
      Rails.logger.info "[SendPlanReportsJob] #{tier}: #{due.join(',')} → #{users.count} destinataire(s)"

      users.find_each do |user|
        due.each do |freq|
          begin
            ReportMailer.nutrition_report(user, plan, frequency: freq).deliver_later
          rescue => e
            Rails.logger.error "[SendPlanReportsJob] #{tier}/#{freq} user #{user.id} (#{user.email}): #{e.message}"
          end
        end
      end
    end
  end

  private

  # daily = tous les jours | weekly = le lundi | monthly = le 1er du mois
  def should_send_today?(frequency, today)
    case frequency
    when "daily"   then true
    when "weekly"  then today.monday?
    when "monthly" then today.day == 1
    else false
    end
  end

  # Utilisateurs actifs du palier avec abonnement non expiré
  def eligible_users_for_tier(tier)
    User.where(plan: tier, status: "active")
        .where("subscription_expires_at IS NULL OR subscription_expires_at > ?", Time.current)
  end
end
