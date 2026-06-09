# Push automatiques par comportement (relance inactifs, fin d'essai, win-back).
# Planifié 1x/jour. Un seul push auto par utilisateur et par jour (cap de fréquence).
# Priorité décroissante : trial_ending > winback > inactive_7d > inactive_3d.
class SendAutoPushJob < ApplicationJob
  queue_as :mailers

  COOLDOWN = 20.hours

  def perform
    fcm = begin
      FcmPushService.new
    rescue FcmPushService::ConfigError => e
      Rails.logger.warn("[AutoPush] FCM non configuré: #{e.message}")
      return
    end

    notified = []
    trigger_scopes.each do |key, scope|
      scope.find_each do |user|
        next if notified.include?(user.id)
        next unless eligible?(user)
        tokens = DeviceToken.where(user: user).pluck(:token)
        next if tokens.empty?

        tpl = PushTemplates.for(key, user.locale)
        res = fcm.send_to_tokens(tokens, title: tpl[:title], body: tpl[:body], data: { type: key.to_s })
        DeviceToken.where(token: res[:invalid]).delete_all if res[:invalid].any?
        if res[:sent] > 0
          user.update_column(:last_auto_push_at, Time.current)
          notified << user.id
        end
      rescue => e
        Rails.logger.error("[AutoPush] user #{user.id}: #{e.message}")
      end
    end
    Rails.logger.info("[AutoPush] #{notified.size} utilisateur(s) notifié(s)")
    notified.size
  end

  # Compte les candidats sans envoyer (diagnostic).
  def self.preview
    job = new
    job.send(:trigger_scopes).transform_values do |scope|
      scope.where(id: DeviceToken.distinct.pluck(:user_id)).count
    end
  end

  private

  def eligible?(user)
    user.last_auto_push_at.nil? || user.last_auto_push_at < COOLDOWN.ago
  end

  def trigger_scopes
    now = Time.current
    {
      trial_ending: User.where(status: "active")
                        .where("trial_ends_at IS NOT NULL AND trial_ends_at BETWEEN ? AND ?", now, now + 2.days),
      winback:      winback_scope,
      inactive_7d:  inactive_scope(7.days),
      inactive_3d:  inactive_scope(3.days, recent_within: 30.days)
    }
  end

  # Utilisateurs actifs (compte) sans usage API depuis `period`, avec un appareil.
  # `recent_within` : ne cibler que ceux qui ont été actifs récemment (re-engagement).
  def inactive_scope(period, recent_within: nil)
    inactive_cutoff = ApiUsage.where("created_at > ?", period.ago).distinct.pluck(:user_id)
    scope = User.where(status: "active").where.not(id: inactive_cutoff)
    if recent_within
      recent_ids = ApiUsage.where("created_at > ?", recent_within.ago).distinct.pluck(:user_id)
      scope = scope.where(id: recent_ids)
    end
    scope.where(id: DeviceToken.distinct.pluck(:user_id))
  end

  # Abonnés récemment expirés, repassés en free/starter.
  def winback_scope
    expired_uids = Subscription.where("expires_at BETWEEN ? AND ?", 30.days.ago, Time.current)
                               .where(status: %w[cancelled expired])
                               .distinct.pluck(:user_id)
    User.where(id: expired_uids, plan: %w[free starter], status: "active")
  end
end
