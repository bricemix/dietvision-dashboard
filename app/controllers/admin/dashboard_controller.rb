module Admin
  class DashboardController < BaseController
    def index
      @total_users      = User.count
      @premium_users    = User.where(plan: "premium").count
      @free_users       = User.where(plan: "free").count
      @new_users_month  = User.where(created_at: Time.current.beginning_of_month..).count

      @total_revenue    = Payment.successful.sum(:amount)
      @revenue_month    = Payment.successful.this_month.sum(:amount)
      @pending_payments = Payment.pending.count

      @api_calls_today  = ApiUsage.today.count
      @api_calls_month  = ApiUsage.this_month.count
      @api_cost_month   = ApiUsage.this_month.total_cost.round(4)

      @recent_users     = User.order(created_at: :desc).limit(5)
      @recent_payments  = Payment.successful.order(paid_at: :desc).limit(5).includes(:user)
    end
  end
end
