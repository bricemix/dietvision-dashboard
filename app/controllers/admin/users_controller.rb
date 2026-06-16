require "csv"

module Admin
  class UsersController < BaseController
    def index
      scope = User.order(created_at: :desc)
      scope = scope.where("name ILIKE ? OR email ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
      scope = scope.where(plan: params[:plan])     if params[:plan].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.in_trial                        if params[:trial] == "1"

      # KPI stats (always on full table, ignoring current filters)
      @stats = {
        total:     User.count,
        active:    User.where(status: "active").count,
        suspended: User.where(status: "suspended").count,
        trial:     User.in_trial.count,
        paid:      User.where(plan: %w[pro starter premium]).count,
        new_week:  User.where("created_at >= ?", 1.week.ago).count
      }

      respond_to do |format|
        format.html do
          @pagy, @users = pagy(scope, limit: 25)
          @plans = Plan.order(:position, :id)
        end
        format.csv do
          users_csv = scope.limit(5000)
          csv_data = CSV.generate(headers: true) do |csv|
            csv << %w[ID Nom Email Pays Plan Statut Essai Inscription Expiration]
            users_csv.each do |u|
              csv << [
                u.id, u.name, u.email, u.country, u.plan, u.status,
                u.in_trial? ? "Oui (J-#{u.trial_days_remaining})" : (u.had_trial? ? "Terminé" : "Non"),
                u.created_at.strftime("%Y-%m-%d"),
                u.subscription_expires_at&.strftime("%Y-%m-%d") || ""
              ]
            end
          end
          send_data csv_data, filename: "utilisateurs-#{Date.today}.csv", type: "text/csv"
        end
      end
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
                     details: { plan: @user.plan },
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
      @api_usages    = @user.api_usages.order(created_at: :desc).limit(50)
      @all_payments  = @user.payments.order(created_at: :desc)
      @fitai_profile = begin; JSON.parse(@user.fitai_profile || '{}'); rescue; {}; end
      @body_entries  = begin; JSON.parse(@user.body_entries_data || '[]'); rescue; []; end
      @planning_data = begin; JSON.parse(@user.planning_data || '{}'); rescue; {}; end
      @usage_by_day  = @user.api_usages.by_day(30)
      @plans         = Plan.order(:position, :id)
    end

    def update
      @user = User.find(params[:id])
      attrs = user_params.to_h

      # Changement de plan → date d'expiration automatique.
      # Un plan payant n'est "actif" (premium?/pro?/vip?) que si la date est future :
      # on la fixe donc à maintenant + durée du plan choisi. free/starter = pas de date.
      if (slug = attrs["plan"]).present?
        plan = Plan.find_by(slug: slug)
        sd   = slug.to_s.downcase
        tier = %w[premium pro vip starter].find { |t| sd.start_with?(t) } || "free"
        attrs["plan"] = tier
        if plan && plan.price_eur_cents.to_i > 0
          attrs["subscription_expires_at"] = Time.current + plan.duration
        elsif %w[free starter].include?(tier)
          attrs["subscription_expires_at"] = nil
        end
      end

      if @user.update(attrs)
        redirect_to admin_user_path(@user), notice: "Utilisateur mis à jour"
      else
        @plans = Plan.order(:position, :id)
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

    def toggle_email_verification
      @user = User.find(params[:id])
      if @user.email_verified?
        @user.update!(email_verified: false, email_verified_at: nil)
        AdminLog.log(admin: current_admin, action: "revoke_email_verification", resource: @user, ip: request.remote_ip)
        redirect_to admin_user_path(@user), notice: "Vérification email révoquée pour #{@user.name}"
      else
        @user.update!(email_verified: true, email_verified_at: Time.current)
        AdminLog.log(admin: current_admin, action: "validate_email_verification", resource: @user, ip: request.remote_ip)
        redirect_to admin_user_path(@user), notice: "Email de #{@user.name} marqué comme vérifié"
      end
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

    # ── Données utilisateur ───────────────────────────────────────
    def data
      @user          = User.find(params[:id])
      @meals_data    = begin; JSON.parse(@user.meals_data    || '[]'); rescue; []; end
      @fitai_profile = begin; JSON.parse(@user.fitai_profile || '{}'); rescue; {}; end
      @body_entries  = begin; JSON.parse(@user.body_entries_data || '[]'); rescue; []; end
      @planning_data = begin; JSON.parse(@user.planning_data || '[]'); rescue; []; end
    end

    # Supprime un type de données (ou toutes)
    # Params : data_type = "meals" | "fitai_profile" | "body_entries" | "planning" | "all"
    def clear_data
      @user = User.find(params[:id])
      type  = params[:data_type].to_s

      notice = case type
      when "meals"
        @user.update!(meals_data: nil)
        AdminLog.log(admin: current_admin, action: "clear_meals", resource: @user, ip: request.remote_ip)
        "#{@user.name} — repas supprimés"
      when "fitai_profile"
        @user.update!(fitai_profile: nil)
        AdminLog.log(admin: current_admin, action: "clear_fitai_profile", resource: @user, ip: request.remote_ip)
        "#{@user.name} — profil nutritionnel supprimé"
      when "body_entries"
        @user.update!(body_entries_data: nil)
        AdminLog.log(admin: current_admin, action: "clear_body_entries", resource: @user, ip: request.remote_ip)
        "#{@user.name} — mesures corporelles supprimées"
      when "planning"
        @user.update!(planning_data: nil)
        AdminLog.log(admin: current_admin, action: "clear_planning", resource: @user, ip: request.remote_ip)
        "#{@user.name} — planning supprimé"
      when "all"
        @user.update!(meals_data: nil, fitai_profile: nil, body_entries_data: nil, planning_data: nil)
        AdminLog.log(admin: current_admin, action: "clear_all_data", resource: @user, ip: request.remote_ip)
        "#{@user.name} — toutes les données supprimées"
      else
        return redirect_to data_admin_user_path(@user), alert: "Type de données inconnu."
      end

      redirect_to data_admin_user_path(@user), notice: notice
    end

    # ── Suppression d'un compte utilisateur ──────────────────────
    def destroy
      unless current_admin.authenticate(params[:confirm_password].to_s)
        return redirect_to admin_user_path(params[:id]),
                           alert: "Mot de passe incorrect — suppression annulée."
      end
      @user = User.find(params[:id])
      email = @user.email
      name  = @user.name
      @user.destroy!
      AdminLog.log(admin: current_admin, action: "delete_user",
                   details: { email: email, name: name }, ip: request.remote_ip)
      redirect_to admin_users_path,
                  notice: "Compte de #{name} (#{email}) supprimé définitivement."
    end

    # ── Vérification cohérence DB ↔ Stripe ───────────────────────
    def stripe_verification
      @issues = _compute_db_issues
      @summary = {
        total_issues: @issues.values.sum(&:size),
        stripe_users: User.where.not(stripe_customer_id: nil).count,
        active_stripe_subs: Subscription.where.not(stripe_subscription_id: nil)
                                        .where(status: "active").count,
        total_payments_stripe: Payment.where(provider: "stripe", status: "success").count,
      }
    end

    # Vérification live via Stripe API (appel réseau — peut être lent)
    def stripe_verification_live
      @issues      = _compute_db_issues
      @live_issues = []

      begin
        require "stripe"
        Stripe.api_key = AppConfig.stripe_secret_key || ENV["STRIPE_SECRET_KEY"] rescue nil

        # Vérifier les abonnements Stripe actifs en DB contre Stripe
        Subscription.where.not(stripe_subscription_id: nil)
                    .where(status: "active")
                    .limit(200).each do |sub|
          begin
            stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id)
            unless %w[active trialing].include?(stripe_sub.status)
              @live_issues << {
                type:    :stripe_status_mismatch,
                user:    sub.user,
                sub:     sub,
                detail:  "DB=active · Stripe=#{stripe_sub.status}",
                action:  "Mettre à jour le statut en '#{stripe_sub.status}'"
              }
            end
          rescue Stripe::InvalidRequestError => e
            @live_issues << {
              type:    :stripe_sub_not_found,
              user:    sub.user,
              sub:     sub,
              detail:  "#{sub.stripe_subscription_id} introuvable sur Stripe",
              action:  "Vérifier ou annuler l'abonnement"
            }
          end
        end

        # Vérifier customers Stripe — abonnement actif sur Stripe mais pas en DB
        User.where.not(stripe_customer_id: nil)
            .where(plan: "free").limit(100).each do |user|
          begin
            subs = Stripe::Subscription.list(customer: user.stripe_customer_id, status: "active", limit: 5)
            if subs.data.any?
              @live_issues << {
                type:    :active_on_stripe_not_in_db,
                user:    user,
                sub:     nil,
                detail:  "#{subs.data.size} abonnement(s) actif(s) sur Stripe mais plan=free en DB",
                action:  "Synchroniser le plan depuis Stripe"
              }
            end
          rescue => e
            # silently skip
          end
        end

        @live_checked = true
      rescue => e
        @live_error = "Erreur Stripe API : #{e.message}"
      end

      render :stripe_verification
    end

    # ── Suppression de TOUS les utilisateurs ─────────────────────
    def destroy_all
      unless current_admin.authenticate(params[:confirm_password].to_s)
        return redirect_to admin_users_path,
                           alert: "Mot de passe incorrect — suppression annulée."
      end
      count = User.count
      User.destroy_all
      AdminLog.log(admin: current_admin, action: "delete_all_users",
                   details: { count: count }, ip: request.remote_ip)
      redirect_to admin_users_path,
                  notice: "#{count} compte(s) utilisateur(s) supprimé(s) définitivement."
    end

    private

    def user_params
      params.require(:user).permit(:name, :plan, :status, :subscription_expires_at)
    end

    # ── Cross-check DB interne (sans appel Stripe API) ───────────
    def _compute_db_issues
      issues = {}

      # 1. Plan premium en DB mais aucun abonnement actif trouvé
      issues[:premium_no_active_sub] = User
        .where.not(plan: "free")
        .where.not(plan: nil)
        .where("subscription_expires_at IS NULL OR subscription_expires_at < ?", Time.current)
        .joins("LEFT JOIN subscriptions ON subscriptions.user_id = users.id
                AND subscriptions.status = 'active'
                AND subscriptions.expires_at > '#{Time.current}'")
        .where("subscriptions.id IS NULL")
        .select(:id, :name, :email, :plan, :subscription_expires_at)
        .limit(50)
        .to_a

      # 2. Abonnement marqué 'active' en DB mais expires_at dépassé
      issues[:sub_active_but_expired] = Subscription
        .includes(:user)
        .where(status: "active")
        .where("expires_at < ?", Time.current)
        .order(expires_at: :desc)
        .limit(50)
        .to_a

      # 3. User.subscription_expires_at ≠ abonnement actif expires_at
      issues[:expires_at_mismatch] = []
      User.where.not(subscription_expires_at: nil)
          .includes(:subscriptions)
          .where("subscription_expires_at > ?", Time.current)
          .limit(200).each do |u|
        active_sub = u.subscriptions.find { |s| s.status == "active" && s.expires_at&.future? }
        next unless active_sub
        diff = (u.subscription_expires_at - active_sub.expires_at).abs
        if diff > 60 # plus de 60 secondes de différence
          issues[:expires_at_mismatch] << { user: u, sub: active_sub, diff_days: (diff / 86400).round }
        end
      end

      # 4. Paiement Stripe success mais abonnement non actif
      issues[:payment_success_no_active_sub] = Payment
        .includes(:user, :subscription)
        .where(provider: "stripe", status: "success")
        .where(paid_at: 30.days.ago..)
        .select { |p|
          p.subscription.nil? ||
          p.subscription.status != "active" ||
          p.subscription.expires_at&.past?
        }
        .first(50)

      # 5. User avec stripe_customer_id mais plan free depuis longtemps
      issues[:stripe_customer_plan_free] = User
        .where.not(stripe_customer_id: nil)
        .where(plan: "free")
        .where("created_at < ?", 7.days.ago)
        .order(created_at: :desc)
        .limit(30)
        .to_a

      # 6. Abonnements Stripe en DB sans customer_id sur l'utilisateur
      issues[:sub_stripe_no_customer] = Subscription
        .includes(:user)
        .where.not(stripe_subscription_id: nil)
        .joins(:user)
        .where("users.stripe_customer_id IS NULL")
        .limit(30)
        .to_a

      issues
    end
  end
end
