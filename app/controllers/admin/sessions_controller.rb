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

      if admin&.authenticate(params[:password])
        session[:admin_id] = admin.id
        admin.update_column(:last_login_at, Time.current)
        redirect_to admin_dashboard_path, notice: "Bienvenue, #{admin.name} !"
      else
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
