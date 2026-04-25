module Admin
  class ApiUsagesController < BaseController
    def index
      scope = ApiUsage.includes(:user).order(created_at: :desc)
      scope = scope.where(endpoint: params[:endpoint]) if params[:endpoint].present?
      scope = scope.where(status: params[:status])     if params[:status].present?

      @pagy, @usages = pagy(scope, limit: 50)

      @total_cost_month = ApiUsage.this_month.total_cost.round(4)
      @calls_today      = ApiUsage.today.count
      @calls_month      = ApiUsage.this_month.count
    end
  end
end
