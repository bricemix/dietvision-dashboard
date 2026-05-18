module Api
  module V1
    class AuthController < BaseController
      skip_authentication :register, :login

      # POST /api/v1/auth/register
      def register
        user = User.new(register_params)
        if user.save
          # Démarrer la période d'essai si activée dans la configuration
          if AppConfig.trial_enabled? && AppConfig.trial_period_days > 0 && !user.had_trial
            user.start_trial!(AppConfig.trial_period_days)
          end
          UserMailer.welcome(user).deliver_now
          token = issue_token(user)
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

        token = issue_token(user)
        render json: { token: token, user: user_json(user) }
      end

      # DELETE /api/v1/auth/logout
      # Invalide la session sur tous les appareils
      def logout
        current_user.update_column(:session_token, nil)
        render json: { message: "Déconnecté avec succès" }
      end

      # GET /api/v1/auth/me
      def me
        render json: user_json(current_user)
      end

      # POST /api/v1/auth/refresh
      def refresh
        # Renouveler le token ET régénérer le session_token (invalide les autres appareils)
        token = issue_token(current_user)
        render json: { token: token }
      end

      private

      # Génère un nouveau session_token UUID, le sauvegarde en base,
      # et retourne un JWT signé contenant ce token.
      def issue_token(user)
        session_token = SecureRandom.uuid
        user.update_column(:session_token, session_token)
        JwtAuthenticatable.encode(user_id: user.id, session_token: session_token)
      end

      def register_params
        source = params[:user].present? ? params.require(:user) : params
        source.permit(:name, :email, :password, :phone, :country)
      end

      def user_json(user)
        {
          id:                      user.id,
          name:                    user.name,
          email:                   user.email,
          phone:                   user.phone,
          country:                 user.country,
          plan:                    user.plan,
          subscription_plan:       user.plan,
          subscription_expires_at: user.subscription_expires_at,
          premium:                 user.premium?,
          trial_ends_at:           user.trial_ends_at,
          in_trial:                user.in_trial?,
          trial_days_remaining:    user.trial_days_remaining
        }
      end
    end
  end
end
