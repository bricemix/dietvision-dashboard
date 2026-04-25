module Api
  module V1
    class ProfileController < BaseController
      # GET /api/v1/profile
      def show
        render json: profile_json
      end

      # PATCH /api/v1/profile
      def update
        if current_user.update(profile_params)
          render json: profile_json
        else
          render json: { error: current_user.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end
      end

      # GET /api/v1/profile/usage
      def usage
        usages = ApiUsage.where(user: current_user)
        render json: {
          today:       usages.today.count,
          this_month:  usages.this_month.count,
          daily_limit: current_user.premium? ? AppConfig.premium_daily_limit : AppConfig.free_daily_limit,
          premium:     current_user.premium?,
          subscription_expires_at: current_user.subscription_expires_at
        }
      end

      private

      def profile_params
        params.require(:user).permit(:name, :phone, :country, :password)
      end

      def profile_json
        {
          id:                      current_user.id,
          name:                    current_user.name,
          email:                   current_user.email,
          phone:                   current_user.phone,
          country:                 current_user.country,
          plan:                    current_user.plan,
          premium:                 current_user.premium?,
          subscription_expires_at: current_user.subscription_expires_at,
          api_calls_today:         ApiUsage.where(user: current_user).today.count,
          daily_limit:             current_user.premium? ? AppConfig.premium_daily_limit : AppConfig.free_daily_limit
        }
      end
    end
  end
end
