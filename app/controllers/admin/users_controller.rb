module Admin
  class UsersController < BaseController
    def index
      scope = User.order(created_at: :desc)
      scope = scope.where("name ILIKE ? OR email ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
      scope = scope.where(plan: params[:plan])     if params[:plan].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.in_trial                        if params[:trial] == "1"

      @pagy, @users = pagy(scope, limit: 25)
      @plans = Plan.order(:position, :id)
    end

    def new
      @user = User.new(status: "active", plan: "free")
    end

    def create
      pwd = params.dig(:user, :password).presence || SecureRandom.hex(10)

      @user = User.new(
        name:    params.dig(:user, :name).to_s.strip,
        email:   params.dig(:user, :email).to_s.strip.downcase,
        country: params.dig(:user, :country).to_s.strip,
        status:  params.dig(:user, :status).presence || "active",
        plan:    params.dig(:user, :plan).presence || "free",
        password: pwd,
        password_confirmation: pwd
      )

      if @user.save
        # Plan premium avec durée
        if @user.plan == "premium"
          days = params.dig(:user, :subscription_days).to_i.clamp(1, 3650)
          @user.update!(subscription_expires_at: Time.current + days.days)
        end

        # Période d'essai — checkbox admin OU config globale si non premium
        if params.dig(:user, :start_trial) == "1"
          trial_days = params.dig(:user, :trial_days).to_i.clamp(1, 90)
          @user.start_trial!(trial_days)
        elsif @user.plan != "premium" && AppConfig.trial_enabled? && AppConfig.trial_period_days > 0 && !@user.had_trial
          @user.start_trial!(AppConfig.trial_period_days)
        end

        AdminLog.log(admin: current_admin, action: "create_user", resource: @user,
                     details: { plan: @user.plan, generated_password: pwd },
                     ip: request.remote_ip)

        redirect_to admin_user_path(@user),
                    notice: "✓ Utilisateur #{@user.name} créé — mot de passe temporaire : #{pwd}"
      else
        flash.now[:alert] = @user.errors.full_messages.join(" · ")
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @user          = User.find(params[:id])
      @subscriptions = @user.subscriptions.order(created_at: :desc)
      @api_usages    = ApiUsage.where(user: @user).order(created_at: :desc).limit(50)  # BUG-10 : réduit de 200 à 50
      @all_payments  = @user.payments.order(created_at: :desc)
      @fitai_profile = begin; JSON.parse(@user.fitai_profile || '{}'); rescue; {}; end
      @body_entries  = begin; JSON.parse(@user.body_entries_data || '[]'); rescue; []; end
      @planning_data = begin; JSON.parse(@user.planning_data || '{}'); rescue; {}; end
      @usage_by_day  = ApiUsage.where(user: @user).by_day(30)
      @plans         = Plan.order(:position, :id)
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
      AdminLog.log(admin: current_admin, action: "suspend_user", resource: @user, ip: request.remote_ip)
      redirect_to admin_users_path, notice: "Compte de #{@user.name} suspendu"
    end

    def activate
      @user = User.find(params[:id])
      @user.update!(status: "active")
      AdminLog.log(admin: current_admin, action: "activate_user", resource: @user, ip: request.remote_ip)
      redirect_to admin_users_path, notice: "Compte de #{@user.name} réactivé"
    end

    # Prolonger un abonnement existant
    def extend_subscription
      @user = User.find(params[:id])
      days  = params[:days].to_i.clamp(1, 365)
      base  = [ @user.subscription_expires_at, Time.current ].compact.max
      @user.update!(plan: "premium", subscription_expires_at: base + days.days)
      AdminLog.log(admin: current_admin, action: "extend_subscription", resource: @user,
                   details: { days: days }, ip: request.remote_ip)
      redirect_to admin_user_path(@user), notice: "Abonnement prolongé de #{days} jours"
    end

    # Offrir un accès premium gratuit
    def gift_access
      @user = User.find(params[:id])
      days  = params[:days].to_i.clamp(1, 365)
      @user.update!(plan: "premium", subscription_expires_at: Time.current + days.days)
      AdminLog.log(admin: current_admin, action: "gift_access", resource: @user,
                   details: { days: days }, ip: request.remote_ip)
      redirect_to admin_user_path(@user), notice: "Accès premium offert pour #{days} jours"
    end

    private

    def user_params
      params.require(:user).permit(:name, :plan, :status, :subscription_expires_at)
    end
  end
end
