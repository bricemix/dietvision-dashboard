module Admin
  class BaseController < ApplicationController
    layout "admin"
    helper :admin

    before_action :authenticate_admin!

    helper_method :current_admin

    private

    def authenticate_admin!
      unless current_admin
        redirect_to admin_login_path, alert: "Connexion requise"
      end
    end

    def current_admin
      @current_admin ||= AdminUser.find_by(id: session[:admin_id])
    end
  end
end
