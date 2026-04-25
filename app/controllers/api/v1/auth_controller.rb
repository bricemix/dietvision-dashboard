module Api
  module V1
    class AuthController < BaseController
      skip_authentication :register, :login

      # POST /api/v1/auth/register
      def register
        user = User.new(register_params)
        if user.save
          token = JwtAuthenticatable.encode(user_id: user.id)
          render json: { token: token, user: user_json(user) }, status: :created
        else
          render json: { error: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/auth/login
      def login
        user = User.find_by(email: params[:email]&.downcase)

        unless user&.authenticate(params[:password])
          return render json: { error: "Email ou mot de passe incorrect" }, status: :unauthorized
        end

        if user.status == "suspended"
          return render json: { error: "Compte suspendu" }, status: :forbidden
        end

        token = JwtAuthenticatable.encode(user_id: user.id)
        render json: { token: token, user: user_json(user) }
      end

      # GET /api/v1/auth/me
      def me
        render json: { user: user_json(current_user) }
      end

      # POST /api/v1/auth/refresh
      def refresh
        token = JwtAuthenticatable.encode(user_id: current_user.id)
        render json: { token: token }
      end

      private

      def register_params
        params.require(:user).permit(:name, :email, :password, :phone, :country)
      end

      def user_json(user)
        {
          id:                      user.id,
          name:                    user.name,
          email:                   user.email,
          phone:                   user.phone,
          country:                 user.country,
          plan:                    user.plan,
          subscription_expires_at: user.subscription_expires_at,
          premium:                 user.premium?
        }
      end
    end
  end
end
