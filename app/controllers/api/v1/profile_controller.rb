require 'json'

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

      # ── FitAI nutrition profile ──────────────────────────────────────────────

      # GET /api/v1/user/fitai
      def fitai_show
        data = parse_json(current_user.fitai_profile)
        render json: { fitai_profile: data }
      end

      # PUT /api/v1/user/fitai  (also aliased as PUT /api/v1/user/profile)
      def fitai_update
        body = json_body
        return if reject_if_too_large!
        # Accept both top-level keys and nested fitai_profile key
        profile_data = body['fitai_profile'] || body

        if current_user.update(fitai_profile: profile_data.to_json)
          render json: { ok: true, fitai_profile: profile_data }
        else
          render json: { error: current_user.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end
      end

      # ── Body entries (mesures corporelles) ──────────────────────────────────

      # GET /api/v1/user/body_entries
      def body_entries_show
        data = parse_json(current_user.body_entries_data)
        render json: { body_entries: data || [] }
      end

      # PUT /api/v1/user/body_entries
      def body_entries_update
        body = json_body
        return if reject_if_too_large!
        entries_data = body['body_entries'] || body

        unless entries_data.is_a?(Array)
          render json: { error: 'Format invalide — attendu un tableau de mesures' }, status: :bad_request
          return
        end

        if current_user.update(body_entries_data: entries_data.to_json)
          render json: { ok: true, entries_saved: entries_data.size }
        else
          render json: { error: current_user.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end
      end

      # ── Meals (historique des repas scannés) ────────────────────────────────

      # GET /api/v1/user/meals
      def meals_show
        data = parse_json(current_user.meals_data)
        render json: { meals: data || [] }
      end

      # PUT /api/v1/user/meals
      def meals_update
        body = json_body
        return if reject_if_too_large!
        meals_data = body['meals'] || body

        unless meals_data.is_a?(Array)
          render json: { error: 'Format invalide — attendu un tableau de repas' }, status: :bad_request
          return
        end

        if current_user.update(meals_data: meals_data.to_json)
          render json: { ok: true, meals_saved: meals_data.size }
        else
          render json: { error: current_user.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end
      end

      # ── Daily missions ──────────────────────────────────────────────────────

      # GET /api/v1/user/missions
      def missions_show
        data = parse_json(current_user.missions_data)
        render json: { missions: data || {} }
      end

      # PUT /api/v1/user/missions
      def missions_update
        body = json_body
        return if reject_if_too_large!
        missions_data = body["missions"] || body

        unless missions_data.is_a?(Hash)
          render json: { error: "Format invalide" }, status: :bad_request
          return
        end

        existing = parse_json(current_user.missions_data) || {}
        merged = existing.merge(missions_data)

        if current_user.update(missions_data: merged.to_json)
          render json: { ok: true, days_saved: merged.size }
        else
          render json: { error: current_user.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end


      # ── Weekly planning ──────────────────────────────────────────────────────

      # GET /api/v1/user/planning
      def planning_show
        data = parse_json(current_user.planning_data)
        render json: { planning: data || [] }
      end

      # PUT /api/v1/user/planning
      def planning_update
        body = json_body
        return if reject_if_too_large!
        # Accept {"planning":[...]} or {"days":[...]} or raw array
        plans_data = body['planning'] || body['days'] || body

        unless plans_data.is_a?(Array)
          render json: { error: 'Format invalide — attendu un tableau de jours' }, status: :bad_request
          return
        end

        if current_user.update(planning_data: plans_data.to_json)
          render json: { ok: true, days_saved: plans_data.size }
        else
          render json: { error: current_user.errors.full_messages.join(", ") },
                 status: :unprocessable_entity
        end
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

      # Lit et parse le corps JSON de la requête (robuste, évite ActionController::Parameters)
      # Taille max d'un blob JSON utilisateur (profil, repas, planning, mesures).
      MAX_JSON_BYTES = 512_000  # 512 Ko

      def json_body
        raw = request.body.read
        request.body.rewind
        return {} if raw.blank?
        @json_too_large = raw.bytesize > MAX_JSON_BYTES
        return {} if @json_too_large
        body = JSON.parse(raw)
        body.is_a?(Hash) ? body : {}
      rescue JSON::ParserError
        {}
      end

      # Rend une 413 si le dernier json_body dépassait la limite. Retourne true si bloqué.
      def reject_if_too_large!
        return false unless @json_too_large
        render json: { error: "Données trop volumineuses (max 512 Ko)" },
               status: :payload_too_large
        true
      end

      def parse_json(raw)
        return nil if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
