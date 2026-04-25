module Api
  module V1
    class PaymentsController < BaseController
      skip_authentication :webhook

      # POST /api/v1/payments/initiate
      # Body: { plan: "monthly"|"yearly", phone: "...", name: "..." }
      def initiate
        plan_key = params[:plan]
        plan_cfg = Subscription::PLANS[plan_key]
        return render json: { error: "Plan invalide" }, status: :bad_request unless plan_cfg

        # Créer la subscription en attente
        subscription = current_user.subscriptions.create!(
          plan:   plan_key,
          amount: plan_cfg[:price],
          status: "pending"
        )

        # Créer le paiement
        payment = current_user.payments.create!(
          subscription: subscription,
          amount:       plan_cfg[:price],
          currency:     "XOF",
          provider:     "cinetpay",
          phone_number: params[:phone],
          status:       "pending"
        )

        # Appel CinetPay
        service = CinetpayService.new
        result  = service.initiate_payment(
          amount:         plan_cfg[:price],
          transaction_id: payment.transaction_id,
          description:    "DietVision #{plan_cfg[:label]}",
          phone:          params[:phone],
          name:           params[:name] || current_user.name,
          notify_url:     api_v1_payments_webhook_url,
          return_url:     "dietvision://payment/callback"
        )

        if result[:error]
          payment.mark_failed!(response: result)
          render json: { error: result[:error] }, status: :unprocessable_entity
        else
          render json: {
            payment_url:    result[:payment_url],
            transaction_id: payment.transaction_id
          }, status: :created
        end
      end

      # GET /api/v1/payments/status/:transaction_id
      def status
        payment = current_user.payments.find_by!(transaction_id: params[:transaction_id])
        render json: {
          status:         payment.status,
          transaction_id: payment.transaction_id,
          amount:         payment.amount,
          paid_at:        payment.paid_at
        }
      end

      # POST /api/v1/payments/webhook  (CinetPay notify_url — public)
      def webhook
        transaction_id = params[:cpm_trans_id] || params[:transaction_id]
        payment        = Payment.find_by(transaction_id: transaction_id)

        return head :not_found unless payment
        return head :ok if payment.status == "success" # idempotent

        service = CinetpayService.new
        result  = service.check_payment(transaction_id)

        case result[:status]
        when "success"
          payment.mark_success!(
            provider_ref: result[:provider_ref],
            response:     result[:raw]
          )
        when "failed"
          payment.mark_failed!(response: result[:raw])
        end

        head :ok
      rescue => e
        Rails.logger.error("CinetPay webhook error: #{e.message}")
        head :ok # toujours 200 pour éviter les retentatives
      end

      # GET /api/v1/payments
      def index
        payments = current_user.payments.order(created_at: :desc).limit(20)
        render json: payments.map { |p|
          {
            transaction_id: p.transaction_id,
            amount:         p.amount,
            status:         p.status,
            plan:           p.subscription&.plan,
            paid_at:        p.paid_at,
            created_at:     p.created_at
          }
        }
      end
    end
  end
end
