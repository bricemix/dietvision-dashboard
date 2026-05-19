module Admin
  class SessionsController < ApplicationController
    layout false

    # GET /admin/login
    def new
      redirect_to admin_dashboard_path if current_admin
    end

    # POST /admin/login
    def create
      admin = AdminUser.find_by(email: params[:email]&.downcase)

      # Vérifier le lockout avant tout (BUG-07)
      if admin&.locked?
        minutes_left = ((admin.locked_until - Time.current) / 60).ceil
        flash.now[:alert] = "Compte temporairement verrouillé. Réessayez dans #{minutes_left} min."
        return render :new, status: :unprocessable_entity
      end

      if admin&.authenticate(params[:password])
        admin.record_successful_login!
        session[:admin_id] = admin.id
        AdminLog.log(admin: admin, action: "login_success",
                     details: { email: admin.email }, ip: request.remote_ip) rescue nil
        redirect_to admin_dashboard_path, notice: "Bienvenue, #{admin.name} !"
      else
        # BUG-15 : logger les échecs + incrémenter le compteur
        admin&.record_failed_login!
        AdminLog.log(admin: nil, action: "login_failed",
                     details: { email: params[:email].to_s.first(100) },
                     ip: request.remote_ip) rescue nil
        flash.now[:alert] = "Email ou mot de passe incorrect"
        render :new, status: :unprocessable_entity
      end
    end

    # DELETE /admin/logout
    def destroy
      session.delete(:admin_id)
      redirect_to admin_login_path, notice: "Déconnecté"
    end

    private

    def current_admin
      @current_admin ||= AdminUser.find_by(id: session[:admin_id])
    end
  end
end
