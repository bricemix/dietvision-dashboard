module Admin
  class PaymentsController < BaseController
    def index
      scope = Payment.includes(:user).order(created_at: :desc)
      scope = scope.where(status:   params[:status])   if params[:status].present?
      scope = scope.where(provider: params[:provider]) if params[:provider].present?

      @total_revenue = Payment.successful.sum(:amount)
      @revenue_month = Payment.successful.this_month.sum(:amount)
      @pending_stripe_count = Payment.where(provider: "stripe", status: "pending").count

      respond_to do |format|
        format.html do
          @pagy, @payments = pagy(scope, limit: 25)
        end
        format.csv do
          @payments = scope.limit(10_000)
          send_data payments_to_csv(@payments),
                    filename: "paiements-#{Date.current}.csv",
                    type: "text/csv; charset=utf-8",
                    disposition: "attachment"
        end
      end
    end

    def show
      @payment = Payment.includes(:user, :subscription).find(params[:id])
    end

    # ── Re-vérification manuelle d'un paiement (Stripe ou CinetPay) ──────────
    def recheck
      @payment = Payment.includes(:subscription, :user).find(params[:id])

      if @payment.provider == "stripe"
        recheck_stripe(@payment)
      else
        recheck_cinetpay(@payment)
      end
    end

    # ── Réparer tous les paiements Stripe pending en bulk ────────────────────
    # Utile quand le webhook n'a pas été reçu pour plusieurs paiements.
    def repair_stripe_pending
      pending = Payment.where(provider: "stripe", status: "pending")
                       .includes(:subscription, :user)

      repaired = 0
      errors   = []

      pending.find_each do |payment|
        session_id = payment.provider_ref
        next unless session_id&.start_with?("cs_")

        begin
          Stripe.api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"]
          session = Stripe::Checkout::Session.retrieve(
            { id: session_id, expand: ["subscription"] }
          )

          next unless session.payment_status == "paid"

          activate_stripe_payment!(payment, session)
          repaired += 1

          AdminLog.log(
            admin:    current_admin,
            action:   "repair_stripe_payment",
            resource: payment,
            details:  { session_id: session_id },
            ip:       request.remote_ip
          )
        rescue => e
          errors << "#{payment.transaction_id}: #{e.message}"
          Rails.logger.error("repair_stripe_pending error for #{payment.transaction_id}: #{e.message}")
        end
      end

      msg = "#{repaired} paiement(s) Stripe réparé(s)"
      msg += " — #{errors.size} erreur(s) : #{errors.first(3).join(', ')}" if errors.any?

      redirect_to admin_payments_path, notice: msg
    end

    private

    # ── Stripe recheck ────────────────────────────────────────────────────────
    def recheck_stripe(payment)
      session_id = payment.provider_ref

      unless session_id&.start_with?("cs_")
        return redirect_to admin_payment_path(payment),
                           alert: "Référence Stripe invalide (attendu cs_xxx, reçu: #{session_id.inspect})"
      end

      begin
        Stripe.api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"]
        session = Stripe::Checkout::Session.retrieve(
          { id: session_id, expand: ["subscription"] }
        )

        unless session.payment_status == "paid"
          return redirect_to admin_payment_path(payment),
                             alert: "Stripe confirme : paiement NON effectué (#{session.payment_status})"
        end

        activate_stripe_payment!(payment, session)

        AdminLog.log(
          admin:    current_admin,
          action:   "recheck_stripe_payment",
          resource: payment,
          details:  { session_id: session_id, status: "repaired" },
          ip:       request.remote_ip
        )

        redirect_to admin_payment_path(payment), notice: "✓ Paiement Stripe confirmé — plan activé"

      rescue Stripe::InvalidRequestError => e
        redirect_to admin_payment_path(payment), alert: "Session Stripe introuvable : #{e.message}"
      rescue => e
        Rails.logger.error("recheck_stripe error: #{e.message}")
        redirect_to admin_payment_path(payment), alert: "Erreur : #{e.message}"
      end
    end

    # ── Activer un paiement Stripe confirmé ───────────────────────────────────
    def activate_stripe_payment!(payment, session)
      subscription = payment.subscription ||
                     payment.user.subscriptions.where(status: %w[pending active])
                                 .order(created_at: :desc).first

      stripe_sub = session.subscription
      expires_at = if stripe_sub.is_a?(Stripe::Subscription)
        Time.at(stripe_sub.current_period_end).utc
      else
        plan_obj = Plan.find_by(slug: subscription&.plan)
        Time.current + (plan_obj&.duration || 1.month)
      end

      ActiveRecord::Base.transaction do
        # 1. Mettre à jour le paiement
        payment.update!(
          status:            "success",
          paid_at:           Time.current,
          provider_response: session.to_json
        )

        # 2. Activer l'abonnement
        if subscription
          sub_id = stripe_sub.is_a?(Stripe::Subscription) ? stripe_sub.id : stripe_sub.to_s
          subscription.update!(
            stripe_subscription_id: sub_id.presence || subscription.stripe_subscription_id,
            status:     "active",
            starts_at:  Time.current,
            expires_at: expires_at
          )
          # 3. Mettre à jour le plan utilisateur
          service    = StripeService.new
          plan_level = service.send(:plan_level_from_subscription, subscription)
          payment.user.update!(
            plan:                    plan_level,
            subscription_expires_at: expires_at
          )
        end
      end
    end

    # ── CinetPay recheck ──────────────────────────────────────────────────────
    def recheck_cinetpay(payment)
      service = CinetpayService.new
      result  = service.check_payment(payment.transaction_id)

      if result[:status] == "success"
        payment.mark_success!(provider_ref: result[:provider_ref], response: result[:raw])
        redirect_to admin_payment_path(payment), notice: "Paiement confirmé ✓"
      else
        redirect_to admin_payment_path(payment), alert: "Statut CinetPay : #{result[:status]}"
      end
    end

    def payments_to_csv(payments)
      require "csv"
      CSV.generate(headers: true, col_sep: ";", encoding: "UTF-8") do |csv|
        csv << %w[ID Date Utilisateur Email Montant_USD Operateur Statut Transaction_ID Telephone Plan]
        payments.each do |p|
          csv << [
            p.id,
            p.created_at.strftime("%d/%m/%Y %H:%M"),
            p.user&.name,
            p.user&.email,
            ("%.2f" % (p.amount.to_i / 100.0)),
            operator_label(p.provider),
            p.status,
            p.transaction_id,
            p.phone_number,
            p.subscription&.plan
          ]
        end
      end
    end

    def operator_label(provider)
      {
        "mvola"        => "MVola",
        "orange_money" => "Orange Money",
        "airtel_money" => "Airtel Money",
        "cinetpay"     => "CinetPay",
        "mtn"          => "MTN",
        "orange"       => "Orange",
        "wave"         => "Wave"
      }[provider] || provider
    end
  end
end
