class PaymentPagesController < ApplicationController
  skip_before_action :verify_authenticity_token
  # La vue est une page HTML autonome (<!DOCTYPE html>) — pas de layout Rails
  layout false

  # GET /payment/success?session_id=cs_xxx
  def success
    @session_id = params[:session_id].to_s.presence
  end

  # GET /payment/cancel
  def cancel
  end

  # GET /payment/portal-return
  # Page affichée quand l'utilisateur revient du Customer Portal Stripe.
  def portal_return
    @locale = params[:locale].to_s
    @locale = 'fr' unless %w[fr en de es pt].include?(@locale)
  end
end
