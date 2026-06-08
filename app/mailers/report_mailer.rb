class ReportMailer < ApplicationMailer

  # ── Traductions du rapport par locale ─────────────────────────────────────
  REPORT_T = {
    "fr" => {
      lang: "fr",
      greeting: "Bonjour",
      subtitle_no_meals: "Vous n'avez enregistré aucun repas sur cette période. Reprenez dès aujourd'hui pour suivre votre progression nutritionnelle !",
      subtitle_balanced: "Excellente période — vos apports caloriques sont parfaitement équilibrés. Voici votre bilan complet.",
      subtitle_deficit:  "Vous êtes en déficit calorique cette période. Bon travail si c'est votre objectif ! Voici votre bilan.",
      subtitle_default:  "Voici votre bilan nutritionnel de la période. Continuez à suivre vos repas pour rester dans vos objectifs.",
      section_key_stats: "Chiffres clés de la période",
      label_meals:       "Repas scannés",
      label_kcal:        "Kcal/jour moy.",
      label_ai:          "Analyses IA",
      label_coach:       "Messages coach",
      kcal_balanced:     "✅ Objectif atteint",
      kcal_deficit:      "💙 Déficit de",
      kcal_surplus:      "🟠 Surplus de",
      kcal_day:          "kcal/j",
      kcal_target:       "cible :",
      kcal_vs:           "vs objectif",
      kcal_text_balanced:"Vos apports sont alignés avec votre objectif. Continuez ainsi !",
      kcal_text_deficit: "Vous consommez moins que votre objectif. Si c'est votre but, bravo ! Sinon, pensez à ajouter des collations riches en protéines.",
      kcal_text_surplus: "Vous dépassez votre objectif quotidien. Essayez de réduire les portions ou d'ajouter une activité physique.",
      section_macros:    "Macronutriments totaux sur la période",
      macro_protein:     "Protéines",
      macro_carbs:       "Glucides",
      macro_fat:         "Lipides",
      section_top_meals: "Aliments les plus caloriques de la période",
      no_meals:          "Aucun repas scanné sur cette période.",
      section_body:      "Progression corporelle",
      body_weight:       "Poids actuel",
      body_evolution:    "Évolution",
      body_measures:     "Mesures enregistrées",
      body_no_data:      "Aucune mesure corporelle enregistrée.",
      body_tdee:         "Objectif TDEE",
      body_diet:         "Régime",
      body_goal:         "Objectif",
      section_ai:        "Activité IA sur la période",
      activity_inactive: "Inactif",
      activity_expert:   "Expert",
      activity_labels:   { inactive: "Aucune activité", low: "Débutant", medium: "Régulier", high: "Expert" },
      activity_msg_inactive: "Reprenez l'application ! Photographiez votre prochain repas pour rester dans vos objectifs.",
      activity_msg_low:      "Un bon début ! Essayez d'analyser au moins un repas par jour.",
      activity_msg_medium:   "Vous êtes sur la bonne voie. Maintenez ce rythme !",
      activity_msg_high:     "Impressionnant ! Vous faites partie des utilisateurs les plus engagés.",
      expiry_title:      "⚠️ Votre abonnement expire bientôt",
      expiry_remaining:  ->(n) { "Il vous reste <strong>#{n} jour#{n > 1 ? 's' : ''}</strong>" },
      expiry_expires:    "expire le",
      expiry_renew:      "Renouvelez dès maintenant pour ne pas perdre votre accès.",
      tip_label:         "Conseil DietVision",
      tips: [
        "Photographiez vos repas dès qu'ils sont servis pour une analyse plus précise des portions.",
        "Posez à votre coach IA des questions spécifiques comme « Quel petit-déjeuner pour augmenter mes protéines ? »",
        "Analysez aussi vos snacks ! Les collations représentent souvent 20 à 30% de l'apport calorique journalier.",
        "Consultez vos graphiques chaque semaine pour identifier vos tendances nutritionnelles.",
        "Boire de l'eau avant chaque repas peut réduire l'apport calorique de 13% en moyenne.",
        "Demandez à votre coach IA un plan de repas sur mesure adapté à vos objectifs du moment.",
      ],
      cta:               "Ouvrir DietVision",
      questions:         "Questions ? Écrivez-nous à",
      footer_prefix:     "Vous recevez ce rapport car vous avez un abonnement",
      footer_suffix:     "DietVision.",
      subject_daily:     "Votre bilan quotidien DietVision",
      subject_weekly:    "Votre bilan hebdomadaire DietVision",
      subject_monthly:   "Votre bilan mensuel DietVision",
      subject_default:   "Votre bilan DietVision",
    },
    "us" => {
      lang: "en",
      greeting: "Hello",
      subtitle_no_meals: "You haven't logged any meals this period. Start today to track your nutritional progress!",
      subtitle_balanced: "Great period — your calorie intake is perfectly balanced. Here's your full report.",
      subtitle_deficit:  "You're in a calorie deficit this period. Well done if that's your goal! Here's your report.",
      subtitle_default:  "Here's your nutritional report for the period. Keep logging your meals to stay on track.",
      section_key_stats: "Key figures for the period",
      label_meals:       "Meals scanned",
      label_kcal:        "Kcal/day avg.",
      label_ai:          "AI analyses",
      label_coach:       "Coach messages",
      kcal_balanced:     "✅ Goal achieved",
      kcal_deficit:      "💙 Deficit of",
      kcal_surplus:      "🟠 Surplus of",
      kcal_day:          "kcal/day",
      kcal_target:       "target:",
      kcal_vs:           "vs goal",
      kcal_text_balanced:"Your intake is aligned with your goal. Keep it up!",
      kcal_text_deficit: "You're eating less than your goal. If that's your aim, great! Otherwise, consider adding protein-rich snacks.",
      kcal_text_surplus: "You're exceeding your daily goal. Try reducing portions or adding physical activity.",
      section_macros:    "Total macronutrients for the period",
      macro_protein:     "Proteins",
      macro_carbs:       "Carbs",
      macro_fat:         "Fat",
      section_top_meals: "Most caloric foods of the period",
      no_meals:          "No meals scanned this period.",
      section_body:      "Body progress",
      body_weight:       "Current weight",
      body_evolution:    "Evolution",
      body_measures:     "Measurements recorded",
      body_no_data:      "No body measurements recorded.",
      body_tdee:         "TDEE goal",
      body_diet:         "Diet",
      body_goal:         "Goal",
      section_ai:        "AI activity for the period",
      activity_inactive: "Inactive",
      activity_expert:   "Expert",
      activity_labels:   { inactive: "No activity", low: "Beginner", medium: "Regular", high: "Expert" },
      activity_msg_inactive: "Come back to the app! Photograph your next meal to stay on track.",
      activity_msg_low:      "A good start! Try to analyze at least one meal per day.",
      activity_msg_medium:   "You're on the right track. Keep up the pace!",
      activity_msg_high:     "Impressive! You're among the most engaged users.",
      expiry_title:      "⚠️ Your subscription expires soon",
      expiry_remaining:  ->(n) { "You have <strong>#{n} day#{n > 1 ? 's' : ''}</strong> left" },
      expiry_expires:    "expires on",
      expiry_renew:      "Renew now so you don't lose access.",
      tip_label:         "DietVision Tip",
      tips: [
        "Photograph your meals as soon as they're served for more accurate portion analysis.",
        'Ask your AI coach specific questions like "What breakfast to boost my protein intake?"',
        "Also analyze your snacks! Snacks often account for 20–30% of daily calorie intake.",
        "Check your charts every week to identify your nutritional trends.",
        "Drinking water before each meal can reduce calorie intake by 13% on average.",
        "Ask your AI coach for a custom meal plan tailored to your current goals.",
      ],
      cta:               "Open DietVision",
      questions:         "Questions? Write to us at",
      footer_prefix:     "You receive this report because you have a",
      footer_suffix:     "DietVision subscription.",
      subject_daily:     "Your daily DietVision report",
      subject_weekly:    "Your weekly DietVision report",
      subject_monthly:   "Your monthly DietVision report",
      subject_default:   "Your DietVision report",
    },
    "de" => {
      lang: "de",
      greeting: "Hallo",
      subtitle_no_meals: "Sie haben in diesem Zeitraum keine Mahlzeiten erfasst. Starten Sie noch heute, um Ihren Ernährungsfortschritt zu verfolgen!",
      subtitle_balanced: "Toller Zeitraum — Ihre Kalorienzufuhr ist perfekt ausgewogen. Hier ist Ihr vollständiger Bericht.",
      subtitle_deficit:  "Sie haben in diesem Zeitraum ein Kaloriendefizit. Gut gemacht, wenn das Ihr Ziel ist! Hier ist Ihr Bericht.",
      subtitle_default:  "Hier ist Ihr Ernährungsbericht für diesen Zeitraum. Erfassen Sie weiterhin Ihre Mahlzeiten, um auf Kurs zu bleiben.",
      section_key_stats: "Wichtigste Zahlen des Zeitraums",
      label_meals:       "Gescannte Mahlzeiten",
      label_kcal:        "Kcal/Tag Ø",
      label_ai:          "KI-Analysen",
      label_coach:       "Coach-Nachrichten",
      kcal_balanced:     "✅ Ziel erreicht",
      kcal_deficit:      "💙 Defizit von",
      kcal_surplus:      "🟠 Überschuss von",
      kcal_day:          "kcal/Tag",
      kcal_target:       "Ziel:",
      kcal_vs:           "vs Ziel",
      kcal_text_balanced:"Ihre Zufuhr stimmt mit Ihrem Ziel überein. Weiter so!",
      kcal_text_deficit: "Sie essen weniger als Ihr Ziel. Wenn das Ihr Ziel ist, super! Andernfalls denken Sie an proteinreiche Snacks.",
      kcal_text_surplus: "Sie überschreiten Ihr Tagesziel. Versuchen Sie, die Portionen zu reduzieren oder mehr Sport zu treiben.",
      section_macros:    "Gesamte Makronährstoffe im Zeitraum",
      macro_protein:     "Proteine",
      macro_carbs:       "Kohlenhydrate",
      macro_fat:         "Fette",
      section_top_meals: "Kalorienreichste Lebensmittel des Zeitraums",
      no_meals:          "Keine Mahlzeiten in diesem Zeitraum erfasst.",
      section_body:      "Körperlicher Fortschritt",
      body_weight:       "Aktuelles Gewicht",
      body_evolution:    "Entwicklung",
      body_measures:     "Erfasste Messungen",
      body_no_data:      "Keine Körpermessungen erfasst.",
      body_tdee:         "TDEE-Ziel",
      body_diet:         "Ernährungsweise",
      body_goal:         "Ziel",
      section_ai:        "KI-Aktivität im Zeitraum",
      activity_inactive: "Inaktiv",
      activity_expert:   "Experte",
      activity_labels:   { inactive: "Keine Aktivität", low: "Anfänger", medium: "Regelmäßig", high: "Experte" },
      activity_msg_inactive: "Kommen Sie zurück zur App! Fotografieren Sie Ihre nächste Mahlzeit.",
      activity_msg_low:      "Ein guter Start! Versuchen Sie, mindestens eine Mahlzeit pro Tag zu analysieren.",
      activity_msg_medium:   "Sie sind auf dem richtigen Weg. Halten Sie das Tempo!",
      activity_msg_high:     "Beeindruckend! Sie gehören zu den engagiertesten Nutzern.",
      expiry_title:      "⚠️ Ihr Abonnement läuft bald ab",
      expiry_remaining:  ->(n) { "Sie haben noch <strong>#{n} Tag#{n > 1 ? 'e' : ''}</strong>" },
      expiry_expires:    "läuft ab am",
      expiry_renew:      "Erneuern Sie jetzt, damit Sie keinen Zugriff verlieren.",
      tip_label:         "DietVision-Tipp",
      tips: [
        "Fotografieren Sie Ihre Mahlzeiten sofort, wenn sie serviert werden, für eine genauere Portionsanalyse.",
        'Stellen Sie Ihrem KI-Coach spezifische Fragen wie "Welches Frühstück erhöht meinen Proteingehalt?"',
        "Analysieren Sie auch Ihre Snacks! Snacks machen oft 20–30% der täglichen Kalorienaufnahme aus.",
        "Überprüfen Sie Ihre Grafiken jede Woche, um Ihre Ernährungstrends zu erkennen.",
        "Wasser vor dem Essen kann die Kalorienaufnahme um durchschnittlich 13% reduzieren.",
        "Bitten Sie Ihren KI-Coach um einen individuellen Ernährungsplan für Ihre aktuellen Ziele.",
      ],
      cta:               "DietVision öffnen",
      questions:         "Fragen? Schreiben Sie uns an",
      footer_prefix:     "Sie erhalten diesen Bericht, weil Sie ein",
      footer_suffix:     "DietVision-Abonnement haben.",
      subject_daily:     "Ihr täglicher DietVision-Bericht",
      subject_weekly:    "Ihr wöchentlicher DietVision-Bericht",
      subject_monthly:   "Ihr monatlicher DietVision-Bericht",
      subject_default:   "Ihr DietVision-Bericht",
    },
    "es" => {
      lang: "es",
      greeting: "Hola",
      subtitle_no_meals: "No has registrado ninguna comida en este período. ¡Empieza hoy para seguir tu progreso nutricional!",
      subtitle_balanced: "¡Excelente período! Tu ingesta calórica está perfectamente equilibrada. Aquí está tu informe completo.",
      subtitle_deficit:  "Tienes un déficit calórico en este período. ¡Bien hecho si ese es tu objetivo! Aquí está tu informe.",
      subtitle_default:  "Aquí está tu informe nutricional del período. Sigue registrando tus comidas para mantenerte en camino.",
      section_key_stats: "Cifras clave del período",
      label_meals:       "Comidas escaneadas",
      label_kcal:        "Kcal/día prom.",
      label_ai:          "Análisis IA",
      label_coach:       "Mensajes coach",
      kcal_balanced:     "✅ Objetivo alcanzado",
      kcal_deficit:      "💙 Déficit de",
      kcal_surplus:      "🟠 Excedente de",
      kcal_day:          "kcal/día",
      kcal_target:       "objetivo:",
      kcal_vs:           "vs objetivo",
      kcal_text_balanced:"Tu ingesta está alineada con tu objetivo. ¡Sigue así!",
      kcal_text_deficit: "Comes menos que tu objetivo. ¡Si ese es tu propósito, genial! Si no, considera añadir snacks ricos en proteínas.",
      kcal_text_surplus: "Estás superando tu objetivo diario. Intenta reducir las porciones o añadir actividad física.",
      section_macros:    "Macronutrientes totales del período",
      macro_protein:     "Proteínas",
      macro_carbs:       "Carbohidratos",
      macro_fat:         "Grasas",
      section_top_meals: "Alimentos más calóricos del período",
      no_meals:          "Ninguna comida escaneada en este período.",
      section_body:      "Progreso corporal",
      body_weight:       "Peso actual",
      body_evolution:    "Evolución",
      body_measures:     "Medidas registradas",
      body_no_data:      "No hay medidas corporales registradas.",
      body_tdee:         "Objetivo TDEE",
      body_diet:         "Dieta",
      body_goal:         "Objetivo",
      section_ai:        "Actividad IA del período",
      activity_inactive: "Inactivo",
      activity_expert:   "Experto",
      activity_labels:   { inactive: "Sin actividad", low: "Principiante", medium: "Regular", high: "Experto" },
      activity_msg_inactive: "¡Vuelve a la app! Fotografía tu próxima comida para mantenerte en tus objetivos.",
      activity_msg_low:      "¡Un buen comienzo! Intenta analizar al menos una comida al día.",
      activity_msg_medium:   "¡Vas por el buen camino. ¡Mantén el ritmo!",
      activity_msg_high:     "¡Impresionante! Eres uno de los usuarios más comprometidos.",
      expiry_title:      "⚠️ Tu suscripción vence pronto",
      expiry_remaining:  ->(n) { "Te quedan <strong>#{n} día#{n > 1 ? 's' : ''}</strong>" },
      expiry_expires:    "vence el",
      expiry_renew:      "Renueva ahora para no perder el acceso.",
      tip_label:         "Consejo DietVision",
      tips: [
        "Fotografía tus comidas en cuanto estén servidas para un análisis más preciso de las porciones.",
        '¡Haz preguntas específicas a tu coach IA como "¿Qué desayuno para aumentar mis proteínas?"',
        "¡Analiza también tus snacks! Los snacks suelen representar el 20-30% de la ingesta calórica diaria.",
        "Revisa tus gráficos cada semana para identificar tus tendencias nutricionales.",
        "Beber agua antes de cada comida puede reducir la ingesta calórica en un 13% de media.",
        "Pide a tu coach IA un plan de comidas personalizado adaptado a tus objetivos actuales.",
      ],
      cta:               "Abrir DietVision",
      questions:         "¿Preguntas? Escríbenos a",
      footer_prefix:     "Recibes este informe porque tienes una suscripción",
      footer_suffix:     "DietVision.",
      subject_daily:     "Tu informe diario DietVision",
      subject_weekly:    "Tu informe semanal DietVision",
      subject_monthly:   "Tu informe mensual DietVision",
      subject_default:   "Tu informe DietVision",
    },
  }.tap { |h| h["en"] = h["us"] }.freeze

  # Rapport nutritionnel périodique envoyé automatiquement aux abonnés d'un plan.
  #
  # @param user  [User]  le destinataire
  # @param plan  [Plan]  le plan auquel l'utilisateur est abonné
  # @param test_recipient [String, nil]  si présent, envoie à cette adresse au lieu de l'utilisateur
  def nutrition_report(user, plan, frequency: nil, test_recipient: nil)
    @user = user
    @plan = plan
    @report_frequency = (frequency || plan.email_report_frequency).to_s

    # ── Données de démo pour l'aperçu test ────────────────────────────────
    if test_recipient.present?
      user.meals_data = [
        { 'date' => Date.current.to_s,        'result' => { 'name' => 'Poulet grillé & légumes verts', 'calories' => 580, 'protein' => 48, 'carbs' => 35, 'fat' => 20, 'healthScore' => 92 } },
        { 'date' => (Date.current - 1).to_s,  'result' => { 'name' => 'Salade César au saumon',        'calories' => 420, 'protein' => 28, 'carbs' => 22, 'fat' => 18, 'healthScore' => 85 } },
        { 'date' => (Date.current - 2).to_s,  'result' => { 'name' => 'Pasta bolognaise maison',       'calories' => 650, 'protein' => 35, 'carbs' => 72, 'fat' => 22, 'healthScore' => 65 } },
        { 'date' => (Date.current - 3).to_s,  'result' => { 'name' => 'Smoothie protéiné banane',      'calories' => 310, 'protein' => 32, 'carbs' => 28, 'fat' =>  8, 'healthScore' => 78 } },
        { 'date' => (Date.current - 4).to_s,  'result' => { 'name' => 'Omelette fromage & épinards',   'calories' => 380, 'protein' => 26, 'carbs' =>  4, 'fat' => 28, 'healthScore' => 70 } },
        { 'date' => (Date.current - 5).to_s,  'result' => { 'name' => 'Riz basmati & dahl lentilles',  'calories' => 490, 'protein' => 22, 'carbs' => 68, 'fat' => 12, 'healthScore' => 80 } },
        { 'date' => (Date.current - 6).to_s,  'result' => { 'name' => 'Steak & patate douce',          'calories' => 620, 'protein' => 52, 'carbs' => 42, 'fat' => 24, 'healthScore' => 88 } },
      ].to_json
      user.body_entries_data = [
        { 'date' => (Date.current - 21).to_s, 'weight' => 79.2, 'bmi' => 24.8 },
        { 'date' => (Date.current - 14).to_s, 'weight' => 78.5, 'bmi' => 24.6 },
        { 'date' => (Date.current -  7).to_s, 'weight' => 77.8, 'bmi' => 24.4 },
        { 'date' => Date.current.to_s,         'weight' => 77.1, 'bmi' => 24.2 },
      ].to_json
      user.fitai_profile = { 'tdee' => 2100, 'goal' => 'Perte de poids', 'dietType' => 'Équilibré' }.to_json
    end

    # ── Données nutrition (depuis meals_data JSON) ──────────────────────────
    period_start = period_start_for
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
    @avg_kcal_day   = @meals_count > 0 ? (@total_kcal.to_f / period_days).round : 0
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

    # ── Langue de l'utilisateur ───────────────────────────────────────────
    @locale = user.locale.presence || "fr"
    @locale = "fr" unless REPORT_T.key?(@locale)
    @t = REPORT_T[@locale]
    @subject = subject_for(@t)

    # ── Période label ─────────────────────────────────────────────────────
    @period_label   = period_label
    @period_start   = period_start_for.strftime("%-d %b")
    @period_end     = Date.current.strftime("%-d %b %Y")
    @frequency_label = Plan::EMAIL_FREQUENCY_LABELS[@report_frequency] || @report_frequency

    # ── Meilleur repas (score santé le plus élevé) ────────────────────────
    @best_meal = @period_meals
      .max_by { |m| (m.dig('result', 'healthScore') || 0).to_i }
      &.dig('result', 'name') || '—'

    # ── Macros % pour le donut SVG ────────────────────────────────────────
    total_macro_kcal = (@total_protein * 4) + (@total_carbs * 4) + (@total_fat * 9)
    if total_macro_kcal > 0
      @prot_pct  = ((@total_protein * 4.0 / total_macro_kcal) * 100).round
      @carbs_pct = ((@total_carbs  * 4.0 / total_macro_kcal) * 100).round
      @fat_pct   = 100 - @prot_pct - @carbs_pct
      circ = 276.46
      @prot_dash  = (@prot_pct  / 100.0 * circ).round(1)
      @carbs_dash = (@carbs_pct / 100.0 * circ).round(1)
      @fat_dash   = (@fat_pct   / 100.0 * circ).round(1)
      @prot_offset  = 0
      @carbs_offset = -@prot_dash
      @fat_offset   = -(@prot_dash + @carbs_dash)
    else
      @prot_pct = @carbs_pct = @fat_pct = 0
      @prot_dash = @carbs_dash = @fat_dash = 0
      @prot_offset = @carbs_offset = @fat_offset = 0
    end

    # ── Checkpoints poids (jusqu'à 4 points pour le graphe) ─────────────
    @weight_checkpoints = (parse_json_array(user.body_entries_data)
      .select { |e| e['weight'].present? && e['date'].present? }
      .sort_by { |e| e['date'].to_s }
      .last(4))

    # ── URLs configurables depuis AppConfig ───────────────────────────────
    default_url    = AppConfig.get("email_app_url").presence || "https://dietvision.app"
    @url_app       = default_url
    @url_scan      = AppConfig.get("email_scan_deeplink").presence      || default_url
    @url_measures  = AppConfig.get("email_measures_deeplink").presence  || default_url
    @url_coach     = AppConfig.get("email_coach_deeplink").presence     || default_url

    # ── Conseil configurable (AppConfig > REPORT_T par défaut) ────────────
    tip_key = "email_report_tip_#{@locale == 'us' ? 'en' : @locale}"
    @report_tip = AppConfig.get(tip_key).presence || @t[:tips][Date.today.cweek % @t[:tips].size]

    # ── Expéditeur et destinataire ────────────────────────────────────────
    to_address = test_recipient.presence || "#{user.name} <#{user.email}>"
    subject_prefix = test_recipient.present? ? "[TEST] " : ""
    sender = AppConfig.get("report_sender_email").presence ||
             AppConfig.get("support_email").presence ||
             "DietVision <noreply@diet-vision.com>"

    mail(
      to:      to_address,
      from:    sender,
      subject: "#{subject_prefix}#{subject_for(@t)} — #{@period_label}"
    )
  end

  private

  def period_start_for
    case @report_frequency
    when 'daily'   then 1.day.ago.beginning_of_day
    when 'weekly'  then 1.week.ago.beginning_of_day
    when 'monthly' then 1.month.ago.beginning_of_day
    else 1.week.ago.beginning_of_day
    end
  end

  def period_days
    case @report_frequency
    when 'daily'   then 1
    when 'weekly'  then 7
    when 'monthly' then 30
    else 7
    end
  end

  def period_label
    case @report_frequency
    when 'daily'   then Date.yesterday.strftime("%-d %B %Y")
    when 'weekly'  then "#{1.week.ago.strftime("%-d %b")} – #{Date.current.strftime("%-d %b %Y")}"
    when 'monthly' then 1.month.ago.strftime("%B %Y").capitalize
    else Date.current.strftime("%B %Y")
    end
  end

  def subject_for(t = REPORT_T["fr"])
    case @report_frequency
    when 'daily'   then t[:subject_daily]
    when 'weekly'  then t[:subject_weekly]
    when 'monthly' then t[:subject_monthly]
    else t[:subject_default]
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
