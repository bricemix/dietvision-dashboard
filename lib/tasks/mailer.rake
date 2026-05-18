namespace :mailer do

  # Envoie le bilan hebdomadaire à tous les utilisateurs premium actifs
  # Usage : bundle exec rails mailer:weekly_digest
  # Cron  : 0 8 * * 1   (chaque lundi à 8h)
  desc "Envoie le bilan hebdomadaire à tous les utilisateurs Premium actifs"
  task weekly_digest: :environment do
    users = User
              .where(status: "active")
              .where(plan: "premium")
              .where("subscription_expires_at IS NULL OR subscription_expires_at > ?", Time.current)
              .order(:id)

    total   = users.count
    success = 0
    failed  = 0

    puts "[#{Time.current.strftime('%Y-%m-%d %H:%M')}] Envoi bilan hebdomadaire — #{total} utilisateur(s) premium"

    users.each do |user|
      PremiumMailer.weekly_digest(user).deliver_now
      success += 1
      puts "  OK  #{user.email}"
    rescue => e
      failed += 1
      puts "  ERR #{user.email} — #{e.message}"
    end

    puts ""
    puts "Termine : #{success} envoyes, #{failed} echecs sur #{total} total"
  end

  # Test sur un seul email (pour vérification avant déploiement cron)
  # Usage : bundle exec rails "mailer:test_weekly[test@example.com]"
  desc "Envoie un bilan de test à l'adresse spécifiée"
  task :test_weekly, [:email] => :environment do |_t, args|
    email = args[:email].presence || "admin@dietvision.app"
    user  = User.find_by(email: email)

    unless user
      # Créer un user factice en mémoire pour le test
      user = User.new(
        name:  "Test Premium",
        email: email,
        plan:  "premium",
        subscription_expires_at: 30.days.from_now
      )
    end

    PremiumMailer.weekly_digest(user).deliver_now
    puts "Bilan de test envoye a : #{email}"
  end

end
