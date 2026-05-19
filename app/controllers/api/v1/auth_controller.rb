module Api
  module V1
    class AuthController < BaseController
      skip_authentication :register, :login, :send_verification, :verify_email,
                          :forgot_password, :reset_password

      # POST /api/v1/auth/register
      def register
        user = User.new(register_params)
        if user.save
          # Démarrer la période d'essai si activée dans la configuration
          if AppConfig.trial_enabled? && AppConfig.trial_period_days > 0 && !user.had_trial
            user.start_trial!(AppConfig.trial_period_days)
          end
          # Envoyer le code de vérification e-mail automatiquement
          # Le mail de bienvenue est envoyé APRÈS validation du code (voir verify_email)
          code = user.generate_verification_code!
          UserMailer.verification_code(user, code).deliver_later
          token = issue_token(user)
          render json: { token: token, user: user_json(user) }, status: :created
        else
          render json: { error: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/auth/send_verification
      # Body: { "email": "user@example.com" }
      def send_verification
        user = User.find_by(email: params[:email]&.downcase)
        return render json: { error: "Utilisateur introuvable" }, status: :not_found unless user
        return render json: { error: "Email déjà vérifié" }, status: :unprocessable_entity if user.email_verified?
        if user.verification_code_cooldown?
          return render json: { error: "Veuillez patienter avant de renvoyer le code", wait: true }, status: :too_many_requests
        end
        code = user.generate_verification_code!
        UserMailer.verification_code(user, code).deliver_later
        render json: { message: "Code envoyé à #{user.email}" }, status: :ok
      end

      # POST /api/v1/auth/verify_email
      # Body: { "email": "user@example.com", "code": "123456" }
      def verify_email
        user = User.find_by(email: params[:email]&.downcase)
        return render json: { error: "Utilisateur introuvable" }, status: :not_found unless user
        return render json: { verified: true, message: "Déjà vérifié" } if user.email_verified?
        if user.verify_email!(params[:code])
          # Email validé → envoyer le mail de bienvenue maintenant
          UserMailer.welcome(user).deliver_later
          render json: { verified: true, user: user_json(user) }, status: :ok
        else
          render json: { verified: false, error: "Code incorrect ou expiré" }, status: :unprocessable_entity
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

      # POST /api/v1/auth/forgot_password
      # Body: { "email": "user@example.com" }
      # Envoie un code de réinitialisation à 6 chiffres valable 1h.
      # Répond toujours 200 (même si l'email est inconnu) pour éviter l'énumération.
      def forgot_password
        user = User.find_by(email: params[:email]&.downcase)
        if user
          if user.password_reset_cooldown?
            return render json: {
              error: "Veuillez patienter avant de demander un nouveau code", wait: true
            }, status: :too_many_requests
          end
          token = user.generate_password_reset_token!
          UserMailer.password_reset(user, token).deliver_later
        end
        render json: { message: "Si cet email existe, un code de réinitialisation a été envoyé." }, status: :ok
      end

      # POST /api/v1/auth/reset_password
      # Body: { "email": "user@example.com", "token": "123456", "password": "NewPass1!" }
      def reset_password
        user = User.find_by(email: params[:email]&.downcase)
        unless user
          return render json: { error: "Utilisateur introuvable" }, status: :not_found
        end
        if user.reset_password_with_token!(params[:token], params[:password])
          render json: { message: "Mot de passe réinitialisé avec succès" }, status: :ok
        else
          render json: { error: "Code invalide, expiré, ou mot de passe non conforme" }, status: :unprocessable_entity
        end
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
        # La période d'essai ne s'applique qu'au plan Starter.
        # Pro et Premium : pas de trial — souscription payante directe uniquement.
        trial_eligible = user.plan.to_s.match?(/\A(free|starter)\z/i)

        # is_active : vrai si abonnement payant actif OU en période d'essai Starter
        active = user.premium? ||
                 user.active_subscription.present? ||
                 (trial_eligible && user.in_trial?)

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
          is_active:               active,
          trial_ends_at:           trial_eligible ? user.trial_ends_at : nil,
          in_trial:                trial_eligible && user.in_trial?,
          trial_days_remaining:    trial_eligible ? user.trial_days_remaining : 0,
          email_verified:          user.email_verified?
        }
      end
    end
  end
end
