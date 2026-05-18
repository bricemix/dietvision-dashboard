class PaymentPagesController < ApplicationController
  skip_before_action :verify_authenticity_token

  # GET /payment/success?session_id=cs_xxx
  def success
    @session_id = params[:session_id]
  end

  # GET /payment/cancel
  def cancel
  end
end
