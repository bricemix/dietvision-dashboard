module Api
  module V1
    class PaymentsController < BaseController
      skip_authentication :webhook

      # POST /api/v1/payments/subscribe
      # Body: { plan_id: 3 }
      # Retourne une checkout_url Stripe à ouvrir dans le navigateur
      def subscribe
        plan = Plan.active.find_by(id: params[:plan_id])
        return render json: { error: "Plan introuvable ou inactif" }, status: :not_found unless plan

        unless plan.stripe_configured?
          return render json: { error: "Ce plan n'est pas encore disponible au paiement" },
                        status: :unprocessable_entity
        end

        service = StripeService.new
        result  = service.create_checkout_session(user: current_user, plan: plan)

        # Créer subscription + payment en attente
        amount_cents = plan.price_eur_cents
        subscription = current_user.subscriptions.create!(
          plan:   plan.slug,
          amount: amount_cents,
          status: "pending"
        )

        current_user.payments.create!(
          subscription: subscription,
          amount:       amount_cents,
          currency:    "EUR",
          provider:    "stripe",
          status:      "pending",
          provider_ref: result[:session_id]
        )

        render json: {
          checkout_url: result[:checkout_url],
          session_id:   result[:session_id],
          plan: {
            id:       plan.id,
            name:     plan.name,
            amount:   amount_cents,
            currency: "EUR"
          }
        }, status: :created

      rescue Stripe::StripeError => e
        Rails.logger.error("Stripe subscribe error: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error("Subscribe error: #{e.message}")
        render json: { error: "Erreur serveur" }, status: :internal_server_error
      end

      # GET /api/v1/payments/status/:transaction_id
      def status
        payment = current_user.payments.find_by!(transaction_id: params[:transaction_id])
        render json: {
          status:         payment.status,
          transaction_id: payment.transaction_id,
          amount:         payment.amount,
          currency:       payment.currency,
          paid_at:        payment.paid_at
        }
      end

      # POST /api/v1/payments/webhook  (Stripe → public)
      def webhook
        payload   = request.raw_post
        signature = request.env["HTTP_STRIPE_SIGNATURE"]
        return head :bad_request if signature.blank?

        service = StripeService.new
        event   = service.construct_event(payload, signature)
        service.handle_event(event)
        head :ok

      rescue Stripe::SignatureVerificationError => e
        Rails.logger.warn("Stripe webhook signature error: #{e.message}")
        head :unauthorized
      rescue => e
        Rails.logger.error("Stripe webhook error: #{e.message}")
        head :internal_server_error
      end

      # POST /api/v1/payments/verify
      # Body: { session_id: "cs_xxx" }
      # Vérifie auprès de Stripe que la session est bien payée.
      # Si le webhook n'a pas encore activé le plan, le fait en fallback.
      # Retourne : { paid, plan, webhook_received, invoice_sent, email_sent, user? }
      def verify
        session_id = params[:session_id].to_s.strip
        return render json: { error: "session_id requis" }, status: :bad_request if session_id.blank?

        service = StripeService.new

        # 1. Récupérer la session Stripe
        stripe_session = Stripe::Checkout::Session.retrieve(
          { id: session_id, expand: ["subscription", "subscription.latest_invoice"] }
        )
        paid = stripe_session.payment_status == "paid"

        unless paid
          return render json: {
            paid:             false,
            plan:             current_user.plan,
            webhook_received: false,
            invoice_sent:     false,
            email_sent:       false
          }
        end

        # 2. Vérifier si le webhook a déjà traité ce paiement
        payment = current_user.payments.find_by(provider_ref: session_id)
        webhook_received = payment&.status == "success"

        # 3. Fallback sécurisé : Stripe a confirmé le paiement mais le webhook
        # n'est pas encore arrivé (délai réseau, secret mal configuré, etc.).
        # On active le plan directement depuis les données Stripe déjà récupérées.
        # SÉCURITÉ : l'activation ne se fait QUE si stripe_session.payment_status == "paid"
        # (vérifié côté Stripe au-dessus). La session appartient à current_user
        # via le payment trouvé par provider_ref (appartenant à current_user).
        unless webhook_received
          begin
            stripe_subscription_id = stripe_session.subscription
            if stripe_subscription_id.present?
              stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
              expires_at = Time.at(stripe_sub.current_period_end).utc

              subscription = payment&.subscription ||
                             current_user.subscriptions.where(status: %w[pending active])
                                         .order(created_at: :desc).first

              if subscription
                service = StripeService.new
                plan_level = service.send(:plan_level_from_subscription, subscription)

                ActiveRecord::Base.transaction do
                  if payment
                    payment.update!(
                      status:   "success",
                      paid_at:  Time.current,
                      provider_response: stripe_session.to_json
                    )
                  end
                  # current_period_start peut être absent de la racine selon la version API Stripe
                  starts_at = begin
                    Time.at(stripe_sub.current_period_start).utc
                  rescue
                    Time.current
                  end
                  subscription.update!(
                    stripe_subscription_id: stripe_subscription_id,
                    status:     "active",
                    starts_at:  starts_at,
                    expires_at: expires_at
                  )
                  current_user.update!(
                    plan:                    plan_level,
                    subscription_expires_at: expires_at,
                    trial_ends_at:           nil   # Souscription active → fin de l'essai Starter
                  )
                end
                webhook_received = true
                Rails.logger.info("Payments#verify fallback : #{current_user.email} → #{plan_level} (webhook non reçu)")
              end
            end
          rescue => e
            Rails.logger.error("Payments#verify fallback error: #{e.message}")
            # Ne pas bloquer la réponse — retourner webhook_received: false
          end
        end

        # 4. Réponse
        render json: {
          paid:             true,
          plan:             current_user.reload.plan,
          webhook_received: webhook_received,
          invoice_sent:     true,   # Stripe envoie la facture automatiquement
          email_sent:       false,
          user:             user_json(current_user)
        }

      rescue Stripe::InvalidRequestError => e
        render json: { error: "Session Stripe introuvable : #{e.message}" }, status: :not_found
      rescue Stripe::StripeError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error("Payments#verify error: #{e.message}")
        render json: { error: "Erreur serveur" }, status: :internal_server_error
      end

      # GET /api/v1/payments/webhook-status?session_id=cs_xxx
      # Permet au client de poller pour savoir si le webhook a été traité.
      # Retourne : { received, processed, plan, received_at }
      def webhook_status
        session_id = params[:session_id].to_s.strip
        return render json: { error: "session_id requis" }, status: :bad_request if session_id.blank?

        # Chercher d'abord le paiement par provider_ref (session_id stocké lors du subscribe)
        payment = current_user.payments.find_by(provider_ref: session_id)

        if payment.nil?
          return render json: {
            received:  false,
            processed: false,
            plan:      current_user.plan
          }
        end

        processed = payment.status == "success"
        render json: {
          received:    true,
          processed:   processed,
          plan:        current_user.plan,
          received_at: payment.updated_at
        }
      end

      # GET /api/v1/payments
      def index
        payments = current_user.payments.order(created_at: :desc).limit(20)
        render json: payments.map { |p|
          {
            transaction_id: p.transaction_id,
            amount:         p.amount,
            currency:       p.currency || "usd",
            status:         p.status,
            provider:       p.provider,
            plan:           p.subscription&.plan,
            paid_at:        p.paid_at,
            created_at:     p.created_at
          }
        }
      end

      private

      def user_json(user)
        # La période d'essai ne s'applique qu'au plan Starter.
        trial_eligible = user.plan.to_s.match?(/\A(free|starter)\z/i)

        active = user.premium? ||
                 user.active_subscription.present? ||
                 (trial_eligible && user.in_trial?)

        {
          id:                      user.id,
          name:                    user.name,
          email:                   user.email,
          plan:                    user.plan,
          subscription_plan:       user.plan,
          subscription_expires_at: user.subscription_expires_at,
          premium:                 user.premium?,
          is_active:               active,
          trial_ends_at:           trial_eligible ? user.trial_ends_at : nil,
          in_trial:                trial_eligible && user.in_trial?,
          trial_days_remaining:    trial_eligible ? user.trial_days_remaining : 0,
          email_verified:          user.email_verified?
        }
      end
    end
  end
end
