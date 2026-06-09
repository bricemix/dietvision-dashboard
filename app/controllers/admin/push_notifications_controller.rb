module Admin
  # Écran admin : composer et envoyer une notification push (FCM).
  class PushNotificationsController < BaseController
    def new
      @total      = DeviceToken.count
      @by_plan    = DeviceToken.joins(:user).group("users.plan").count
      @by_plat    = DeviceToken.group(:platform).count
    end

    def create
      title  = params[:title].to_s.strip
      body   = params[:body].to_s.strip
      target = params[:target].to_s

      if title.blank? || body.blank?
        return redirect_to admin_push_notifications_path, alert: "Titre et message obligatoires."
      end

      tokens = tokens_for_target(target)
      if tokens.empty?
        return redirect_to admin_push_notifications_path, alert: "Aucun appareil enregistré pour cette cible."
      end

      result = FcmPushService.new.send_to_tokens(tokens, title: title, body: body)
      DeviceToken.where(token: result[:invalid]).delete_all if result[:invalid].any?

      msg = "Notification envoyée — #{result[:sent]} reçue(s), #{result[:failed]} échec(s)"
      msg += ", #{result[:invalid].size} token(s) obsolète(s) purgé(s)" if result[:invalid].any?
      redirect_to admin_push_notifications_path, notice: msg
    rescue FcmPushService::ConfigError => e
      redirect_to admin_push_notifications_path, alert: "Configuration FCM manquante : #{e.message}"
    rescue => e
      Rails.logger.error("[Admin::Push] #{e.class}: #{e.message}")
      redirect_to admin_push_notifications_path, alert: "Erreur d'envoi : #{e.message}"
    end

    private

    def tokens_for_target(target)
      scope = DeviceToken.joins(:user)
      scope =
        case target
        when "all"
          scope
        when /\Aplan:(.+)\z/
          scope.where(users: { plan: Regexp.last_match(1) })
        when "inactive7"
          active_ids = ApiUsage.where("created_at > ?", 7.days.ago).distinct.pluck(:user_id)
          active_ids.any? ? scope.where.not(users: { id: active_ids }) : scope
        else
          DeviceToken.none
        end
      scope.distinct.pluck(:token)
    end
  end
end
