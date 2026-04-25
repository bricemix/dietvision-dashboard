module Admin
  class PaymentsController < BaseController
    def index
      scope = Payment.includes(:user).order(created_at: :desc)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(provider: params[:provider]) if params[:provider].present?

      @pagy, @payments = pagy(scope, limit: 25)

      @total_revenue  = Payment.successful.sum(:amount)
      @revenue_month  = Payment.successful.this_month.sum(:amount)
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
  end
end
