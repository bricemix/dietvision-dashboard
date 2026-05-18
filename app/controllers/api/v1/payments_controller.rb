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
    end
  end
end
