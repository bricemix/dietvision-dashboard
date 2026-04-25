module Admin
  class UsersController < BaseController
    def index
      scope = User.order(created_at: :desc)
      scope = scope.where("name ILIKE ? OR email ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
      scope = scope.where(plan: params[:plan]) if params[:plan].present?
      scope = scope.where(status: params[:status]) if params[:status].present?

      @pagy, @users = pagy(scope, limit: 25)
    end

    def show
      @user         = User.find(params[:id])
      @subscriptions = @user.subscriptions.order(created_at: :desc)
      @payments      = @user.payments.order(created_at: :desc).limit(10)
      @api_usages    = ApiUsage.where(user: @user).order(created_at: :desc).limit(20)
      @usage_by_day  = ApiUsage.where(user: @user).by_day(30)
    end

    def update
      @user = User.find(params[:id])
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "Utilisateur mis à jour"
      else
        render :show, status: :unprocessable_entity
      end
    end

    def suspend
      @user = User.find(params[:id])
      @user.update!(status: "suspended")
      redirect_to admin_users_path, notice: "Compte suspendu"
    end

    def activate
      @user = User.find(params[:id])
      @user.update!(status: "active")
      redirect_to admin_users_path, notice: "Compte activé"
    end

    private

    def user_params
      params.require(:user).permit(:name, :plan, :status, :subscription_expires_at)
    end
  end
end
