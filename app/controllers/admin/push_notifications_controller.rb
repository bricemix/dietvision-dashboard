module Admin
  # Écran admin : composer et envoyer une notification push (FCM),
  # avec traduction automatique IA dans la langue de chaque utilisateur.
  class PushNotificationsController < BaseController
    def new
      @total   = DeviceToken.count
      @by_plan = DeviceToken.joins(:user).group("users.plan").count
      @by_plat = DeviceToken.group(:platform).count
    end

    def create
      title   = params[:title].to_s.strip
      body    = params[:body].to_s.strip
      target  = params[:target].to_s
      auto_tr = params[:auto_translate].to_s == "1"

      if title.blank? || body.blank?
        return redirect_to admin_push_notifications_path, alert: "Titre et message obligatoires."
      end

      rows = device_rows_for_target(target) # [[token, locale], ...]
      if rows.empty?
        return redirect_to admin_push_notifications_path, alert: "Aucun appareil enregistré pour cette cible."
      end

      fcm = FcmPushService.new
      total = { sent: 0, failed: 0, invalid: [] }

      if auto_tr
        langs = rows.map { |_, loc| norm_locale(loc) }.uniq
        trans = OpenrouterService.new.translate_push(title: title, body: body, langs: langs)
        rows.group_by { |_, loc| norm_locale(loc) }.each do |loc, group|
          t = trans[loc] || {}
          tok = group.map(&:first)
          res = fcm.send_to_tokens(tok,
                                   title: t["title"].presence || title,
                                   body:  t["body"].presence  || body)
          merge_result(total, res)
        end
      else
        res = fcm.send_to_tokens(rows.map(&:first), title: title, body: body)
        merge_result(total, res)
      end

      DeviceToken.where(token: total[:invalid]).delete_all if total[:invalid].any?

      msg = "Notification envoyée — #{total[:sent]} reçue(s), #{total[:failed]} échec(s)"
      msg += " · traduite (IA) dans #{rows.map { |_, l| norm_locale(l) }.uniq.size} langue(s)" if auto_tr
      msg += " · #{total[:invalid].size} token(s) obsolète(s) purgé(s)" if total[:invalid].any?
      redirect_to admin_push_notifications_path, notice: msg
    rescue FcmPushService::ConfigError => e
      redirect_to admin_push_notifications_path, alert: "Configuration FCM manquante : #{e.message}"
    rescue => e
      Rails.logger.error("[Admin::Push] #{e.class}: #{e.message}")
      redirect_to admin_push_notifications_path, alert: "Erreur d'envoi : #{e.message}"
    end

    private

    def norm_locale(loc)
      l = loc.to_s.downcase
      l = "en" if l == "us" || l.blank?
      %w[fr en de es pt].include?(l) ? l : "fr"
    end

    def merge_result(acc, res)
      acc[:sent]    += res[:sent].to_i
      acc[:failed]  += res[:failed].to_i
      acc[:invalid] += Array(res[:invalid])
    end

    # Retourne [[token, locale], ...] pour la cible.
    def device_rows_for_target(target)
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
      scope.distinct.pluck("device_tokens.token", "users.locale")
    end
  end
end
