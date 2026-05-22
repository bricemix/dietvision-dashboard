class ReportMailer < ApplicationMailer

  # Rapport nutritionnel périodique envoyé automatiquement aux abonnés d'un plan.
  #
  # @param user  [User]  le destinataire
  # @param plan  [Plan]  le plan auquel l'utilisateur est abonné
  # @param test_recipient [String, nil]  si présent, envoie à cette adresse au lieu de l'utilisateur
  def nutrition_report(user, plan, test_recipient: nil)
    @user = user
    @plan = plan

    # ── Données nutrition (depuis meals_data JSON) ──────────────────────────
    period_start = period_start_for(plan)
    all_meals    = parse_json_array(user.meals_data)

    @period_meals = all_meals.select do |m|
      begin
        DateTime.parse(m['date'].to_s) >= period_start
      rescue
        false
      end
    end

    @meals_count    = @period_meals.length
    @total_kcal     = @period_meals.sum { |m| (m.dig('result', 'calories') || 0).to_i }
    @avg_kcal_day   = @meals_count > 0 ? (@total_kcal.to_f / period_days(plan)).round : 0
    @total_protein  = @period_meals.sum { |m| (m.dig('result', 'protein') || 0).to_f }.round(1)
    @total_carbs    = @period_meals.sum { |m| (m.dig('result', 'carbs')   || 0).to_f }.round(1)
    @total_fat      = @period_meals.sum { |m| (m.dig('result', 'fat')     || 0).to_f }.round(1)

    # Top 5 aliments de la période
    @top_meals = @period_meals
      .sort_by { |m| -(m.dig('result', 'calories') || 0).to_i }
      .first(5)

    # ── Profil nutritionnel ────────────────────────────────────────────────
    fitai = parse_json_hash(user.fitai_profile)
    @tdee         = fitai['tdee']&.round || 0
    @goal         = fitai['goal'] || '—'
    @diet_type    = fitai['dietType'] || '—'
    @target_kcal  = @tdee

    # Déficit / surplus moyen sur la période
    if @target_kcal > 0 && @avg_kcal_day > 0
      diff = @avg_kcal_day - @target_kcal
      @kcal_status = diff < -50 ? :deficit : diff > 50 ? :surplus : :balanced
      @kcal_diff   = diff.abs
    else
      @kcal_status = :unknown
      @kcal_diff   = 0
    end

    # ── Progression corporelle ─────────────────────────────────────────────
    entries = parse_json_array(user.body_entries_data)
      .select { |e| e['weight'].present? }
      .sort_by { |e| e['date'].to_s }

    @latest_weight  = entries.last&.dig('weight')
    @previous_weight = entries.length >= 2 ? entries[-2]&.dig('weight') : nil
    @weight_delta   = (@latest_weight && @previous_weight) ?
                        (@latest_weight.to_f - @previous_weight.to_f).round(1) : nil

    @body_entries_count = entries.length

    # ── Activité IA ────────────────────────────────────────────────────────
    usages = user.api_usages.where(created_at: period_start..)
    @ai_analyses  = usages.where(endpoint: "analyze_food").count
    @ai_coach     = usages.where(endpoint: "coach_chat").count
    @ai_total     = usages.count

    @activity_level = case @ai_analyses
                      when 0     then :inactive
                      when 1..3  then :low
                      when 4..10 then :medium
                      else            :high
                      end

    # ── Abonnement ────────────────────────────────────────────────────────
    @expires_at     = user.subscription_expires_at
    @days_remaining = @expires_at ? ((@expires_at - Time.current) / 1.day).ceil : nil
    @expiry_warning = @days_remaining && @days_remaining <= 7 && @days_remaining > 0

    # ── Période label ─────────────────────────────────────────────────────
    @period_label = period_label(plan)
    @frequency_label = Plan::EMAIL_FREQUENCY_LABELS[plan.email_report_frequency] || plan.email_report_frequency

    # ── Expéditeur et destinataire ────────────────────────────────────────
    to_address = test_recipient.presence || "#{user.name} <#{user.email}>"
    subject_prefix = test_recipient.present? ? "[TEST] " : ""
    sender = AppConfig.get("report_sender_email").presence ||
             AppConfig.get("support_email").presence ||
             "DietVision <noreply@diet-vision.com>"
    # sender est déjà défini via application_mailer si non surchargé

    mail(
      to:      to_address,
      from:    sender,
      subject: "#{subject_prefix}#{subject_for(plan)} — #{@period_label}"
    )
  end

  private

  def period_start_for(plan)
    case plan.email_report_frequency
    when 'daily'   then 1.day.ago.beginning_of_day
    when 'weekly'  then 1.week.ago.beginning_of_day
    when 'monthly' then 1.month.ago.beginning_of_day
    else 1.week.ago.beginning_of_day
    end
  end

  def period_days(plan)
    case plan.email_report_frequency
    when 'daily'   then 1
    when 'weekly'  then 7
    when 'monthly' then 30
    else 7
    end
  end

  def period_label(plan)
    case plan.email_report_frequency
    when 'daily'   then Date.yesterday.strftime("%-d %B %Y")
    when 'weekly'  then "#{1.week.ago.strftime("%-d %b")} – #{Date.current.strftime("%-d %b %Y")}"
    when 'monthly' then 1.month.ago.strftime("%B %Y").capitalize
    else Date.current.strftime("%B %Y")
    end
  end

  def subject_for(plan)
    case plan.email_report_frequency
    when 'daily'   then "Votre bilan quotidien DietVision"
    when 'weekly'  then "Votre bilan hebdomadaire DietVision"
    when 'monthly' then "Votre bilan mensuel DietVision"
    else "Votre bilan DietVision"
    end
  end

  def parse_json_array(raw)
    return [] if raw.blank?
    data = JSON.parse(raw)
    data.is_a?(Array) ? data : []
  rescue JSON::ParserError
    []
  end

  def parse_json_hash(raw)
    return {} if raw.blank?
    data = JSON.parse(raw)
    data.is_a?(Hash) ? data : {}
  rescue JSON::ParserError
    {}
  end
end
