module Admin
  class TrialController < BaseController

    def index
      # Config actuelle
      @trial_enabled        = AppConfig.get("trial_enabled") != "false"
      @trial_days           = AppConfig.get("trial_days")&.to_i || 7
      @trial_message        = AppConfig.get("trial_expiry_message").to_s
      @trial_max_per_device = AppConfig.get("trial_max_per_device")&.to_i || 1
      @trial_features       = JSON.parse(AppConfig.get("trial_features") || "{}") rescue {}

      # Stats
      @total_in_trial  = User.in_trial.count
      @expired_trials  = User.trial_expired.count
      @converted       = User.where(had_trial: true, plan: "premium").count

      # Liste utilisateurs en essai
      scope = User.in_trial
      scope = scope.where("name ILIKE ? OR email ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
      @pagy, @trial_users = pagy(scope.order("trial_ends_at ASC"), limit: 20)
    end

    def update_config
      AppConfig.set("trial_enabled",        params[:trial_enabled].to_s)
      AppConfig.set("trial_days",           params[:trial_days].to_s)
      AppConfig.set("trial_expiry_message", params[:trial_expiry_message].to_s)
      AppConfig.set("trial_max_per_device", params[:trial_max_per_device].to_s)

      features = {}
      %w[scan_ai chatbot graphs pdf_export].each do |f|
        features[f] = params.dig(:trial_features, f) == "1"
      end
      AppConfig.set("trial_features", features.to_json)

      AdminLog.log(admin: current_admin, action: "update_trial_config", ip: request.remote_ip)
      redirect_to admin_trial_path, notice: "Configuration essai mise à jour"
    end

    def extend_user_trial
      user = User.find(params[:user_id])
      days = params[:days].to_i.clamp(1, 90)
      base = [ user.trial_ends_at, Time.current ].compact.max
      user.update!(trial_ends_at: base + days.days)
      AdminLog.log(admin: current_admin, action: "extend_user_trial", resource: user,
                   details: { days: days }, ip: request.remote_ip)
      redirect_to admin_trial_path, notice: "Essai de #{user.name} prolongé de #{days} jours"
    end
  end
end
