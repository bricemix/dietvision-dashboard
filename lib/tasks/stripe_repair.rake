namespace :stripe do
  # ── Réparer les paiements bloqués en "pending" ────────────────────────────────
  # Certains paiements ont été créés avec provider_ref = checkout_session_id (cs_xxx)
  # mais le webhook invoice.paid utilisait payment_intent_id (pi_xxx) comme clé,
  # créant un doublon "success" au lieu de mettre à jour l'original.
  #
  # Usage :
  #   rails stripe:repair_pending_payments            → mode dry-run (aucune modif)
  #   rails stripe:repair_pending_payments DRY=false  → mode réel
  #
  desc "Répare les paiements Stripe bloqués en 'pending' en réconciliant avec Stripe"
  task repair_pending_payments: :environment do
    dry_run = ENV.fetch("DRY", "true") != "false"
    puts dry_run ? "[DRY RUN] Aucune modification ne sera effectuée." : "[LIVE] Modifications en base."

    Stripe.api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"]

    pending_stripe = Payment.where(provider: "stripe", status: "pending")
                            .includes(:subscription, :user)

    puts "#{pending_stripe.count} paiement(s) Stripe pending trouvé(s)."

    pending_stripe.find_each do |payment|
      session_id = payment.provider_ref
      next unless session_id&.start_with?("cs_")

      print "  #{payment.transaction_id} (#{session_id}) → "

      begin
        session = Stripe::Checkout::Session.retrieve(
          { id: session_id, expand: ["subscription"] }
        )

        if session.payment_status != "paid"
          puts "non payé sur Stripe (#{session.payment_status}) — ignoré"
          next
        end

        stripe_sub = session.subscription
        expires_at = stripe_sub.is_a?(Stripe::Subscription) \
          ? Time.at(stripe_sub.current_period_end).utc \
          : Time.current + 30.days

        subscription = payment.subscription ||
                       payment.user.subscriptions.where(status: %w[pending active])
                                   .order(created_at: :desc).first

        plan_level = if subscription
          service = StripeService.new
          service.send(:plan_level_from_subscription, subscription)
        else
          "premium"
        end

        puts "PAYÉ — sera activé → plan=#{plan_level}, expires=#{expires_at.strftime('%d/%m/%Y')}"

        unless dry_run
          ActiveRecord::Base.transaction do
            payment.update!(
              status:   "success",
              paid_at:  Time.current,
              provider_response: session.to_json
            )
            if subscription
              subscription.update!(
                stripe_subscription_id: stripe_sub.is_a?(Stripe::Subscription) ? stripe_sub.id : stripe_sub.to_s,
                status:     "active",
                expires_at: expires_at
              )
            end
            payment.user.update!(
              plan:                    plan_level,
              subscription_expires_at: expires_at
            )
          end
          puts "    ✓ Corrigé."
        end

      rescue Stripe::InvalidRequestError => e
        puts "Session Stripe introuvable : #{e.message}"
      rescue => e
        puts "ERREUR : #{e.message}"
      end
    end

    puts "\nTerminé."
  end
end
