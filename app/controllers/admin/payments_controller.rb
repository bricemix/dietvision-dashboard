module Admin
  class PaymentsController < BaseController
    def index
      scope = Payment.includes(:user).order(created_at: :desc)
      scope = scope.where(status:   params[:status])   if params[:status].present?
      scope = scope.where(provider: params[:provider]) if params[:provider].present?

      @total_revenue = Payment.successful.sum(:amount)
      @revenue_month = Payment.successful.this_month.sum(:amount)

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

    # Re-vérification manuelle du statut via CinetPay
    def recheck
      @payment = Payment.find(params[:id])
      service  = CinetpayService.new
      result   = service.check_payment(@payment.transaction_id)

      if result[:status] == "success"
        @payment.mark_success!(provider_ref: result[:provider_ref], response: result[:raw])
        redirect_to admin_payment_path(@payment), notice: "Paiement confirmé ✓"
      else
        redirect_to admin_payment_path(@payment), alert: "Statut: #{result[:status]}"
      end
    end

    private

    def payments_to_csv(payments)
      require "csv"
      CSV.generate(headers: true, col_sep: ";", encoding: "UTF-8") do |csv|
        csv << %w[ID Date Utilisateur Email Montant_Ar Operateur Statut Transaction_ID Telephone Plan]
        payments.each do |p|
          csv << [
            p.id,
            p.created_at.strftime("%d/%m/%Y %H:%M"),
            p.user&.name,
            p.user&.email,
            p.amount.to_i,
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
