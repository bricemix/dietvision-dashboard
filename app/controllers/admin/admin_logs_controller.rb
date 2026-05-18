module Admin
  class AdminLogsController < BaseController
    def index
      scope = AdminLog.includes(:admin_user).recent
      scope = scope.where(action: params[:action_filter]) if params[:action_filter].present?
      scope = scope.where(admin_user_id: params[:admin_id]) if params[:admin_id].present?
      @pagy, @logs = pagy(scope, limit: 50)
    end
  end
end
