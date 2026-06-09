class OpenrouterService
  BASE_URL = "https://openrouter.ai/api/v1/"  # trailing slash obligatoire pour Faraday

  def initialize(user:)
    @user   = user
    @api_key = AppConfig.openrouter_api_key
  end

  # Analyse une image alimentaire (base64 JPEG)
  # Text-only food analysis (no image)
  def analyze_food_text(description, meal_type: nil, model: nil, locale: "fr")
    model ||= AppConfig.vision_model
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    context = description.strip
    context += "
Type de repas / Meal type: #{meal_type}" if meal_type.present?

    payload = {
      model: model,
      max_tokens: 800,
      messages: [
        {
          role: "user",
          content: food_analysis_prompt(locale) + "

Description du repas: #{context}"
        }
      ]
    }

    response   = post("chat/completions", payload)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    data       = parse_response(response)

    if response.success? && !data["error"]
      text  = data.dig("choices", 0, "message", "content")
      usage = data["usage"] || {}
      record_usage(endpoint: "analyze_food", model: model,
                   input_tokens: usage["prompt_tokens"].to_i,
                   output_tokens: usage["completion_tokens"].to_i,
                   duration_ms: duration_ms, status: "success")
      parse_json_response(text)
    else
      err = data["error"]
      msg = err.is_a?(Hash) ? err["message"].to_s : err.to_s
      msg = "Analyse échouée (#{response.status})" if msg.blank?
      record_usage(endpoint: "analyze_food", model: model, status: "error",
                   duration_ms: duration_ms, error_message: msg)
      { error: msg }
    end
  rescue => e
    { error: e.message }
  end

  def analyze_food(base64_image, model: nil, locale: "fr", description: nil)
    model ||= AppConfig.vision_model
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    payload = {
      model: model,
      max_tokens: 800,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image_url",
              image_url: { url: "data:image/jpeg;base64,#{base64_image}" }
            },
            {
              type: "text",
              text: [food_analysis_prompt(locale), description.presence && "Note: #{description}"].compact.join("
")
            }
          ]
        }
      ]
    }

    response = post("chat/completions", payload)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    data = parse_response(response)

    if response.success? && !data["error"]
      text   = data.dig("choices", 0, "message", "content")
      usage  = data["usage"] || {}
      record_usage(endpoint: "analyze_food", model: model,
                   input_tokens: usage["prompt_tokens"].to_i,
                   output_tokens: usage["completion_tokens"].to_i,
                   duration_ms: duration_ms, status: "success")
      parse_json_response(text)
    else
      err_detail = data["error"]
      err_msg = err_detail.is_a?(Hash) ? err_detail["message"].to_s : err_detail.to_s
      err_msg = "Analyse échouée (#{response.status})" if err_msg.blank?
      Rails.logger.error("OpenRouter analyze_food API error (#{response.status}): #{err_msg}")
      record_usage(endpoint: "analyze_food", model: model, status: "error", duration_ms: duration_ms,
                   error_message: "HTTP #{response.status} — #{err_msg}")
      { error: err_msg }
    end
  rescue => e
    duration_ms = defined?(start_time) ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round : 0
    Rails.logger.error("OpenRouter analyze_food error [#{e.class}]: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
    record_usage(endpoint: "analyze_food", model: model || "unknown", status: "error", duration_ms: duration_ms,
                 error_message: "[#{e.class}] #{e.message}")
    { error: e.message }
  end

  # Coach IA — messages est un array [{role:, content:}]
  def coach_chat(messages, profile:, model: nil, locale: "fr", max_tokens: nil, today_context: {})
    model ||= AppConfig.default_model
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    system_msg = {
      role: "system",
      content: coach_system_prompt(profile, locale, today_context)
    }

    payload = {
      model: model,
      max_tokens: max_tokens || 400,
      messages: [ system_msg ] + messages
    }

    response = post("chat/completions", payload)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    data = parse_response(response)

    if response.success? && !data["error"]
      text   = data.dig("choices", 0, "message", "content")
      usage  = data["usage"] || {}
      record_usage(endpoint: "coach_chat", model: model,
                   input_tokens: usage["prompt_tokens"].to_i,
                   output_tokens: usage["completion_tokens"].to_i,
                   duration_ms: duration_ms, status: "success")
      { reply: text }
    else
      err_detail = data["error"]
      err_msg = err_detail.is_a?(Hash) ? err_detail["message"].to_s : err_detail.to_s
      err_msg = "Coach indisponible (#{response.status})" if err_msg.blank?
      Rails.logger.error("OpenRouter coach_chat API error (#{response.status}): #{err_msg}")
      record_usage(endpoint: "coach_chat", model: model, status: "error", duration_ms: duration_ms,
                   error_message: "HTTP #{response.status} — #{err_msg}")
      { error: err_msg }
    end
  rescue => e
    duration_ms = defined?(start_time) ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round : 0
    Rails.logger.error("OpenRouter coach_chat error [#{e.class}]: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
    record_usage(endpoint: "coach_chat", model: model || "unknown", status: "error", duration_ms: duration_ms,
                 error_message: "[#{e.class}] #{e.message}")
    { error: e.message }
  end

  # Recommandations de plats — appel dédié, tracé séparément (endpoint: dish_recommendation)
  def dish_recommendations(messages, profile:, model: nil, locale: "fr", max_tokens: nil)
    model ||= AppConfig.default_model
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Pas de system_prompt coach ici — le prompt utilisateur contient toutes les instructions
    payload = {
      model:      model,
      max_tokens: max_tokens || 1800,
      messages:   messages
    }

    response = post("chat/completions", payload)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    data = parse_response(response)

    if response.success? && !data["error"]
      text  = data.dig("choices", 0, "message", "content")
      usage = data["usage"] || {}
      record_usage(endpoint: "dish_recommendation", model: model,
                   input_tokens: usage["prompt_tokens"].to_i,
                   output_tokens: usage["completion_tokens"].to_i,
                   duration_ms: duration_ms, status: "success")
      { reply: text }
    else
      err_detail = data["error"]
      err_msg = err_detail.is_a?(Hash) ? err_detail["message"].to_s : err_detail.to_s
      err_msg = "Recommandation indisponible (#{response.status})" if err_msg.blank?
      Rails.logger.error("OpenRouter dish_recommendation API error (#{response.status}): #{err_msg}")
      record_usage(endpoint: "dish_recommendation", model: model, status: "error", duration_ms: duration_ms,
                   error_message: "HTTP #{response.status} — #{err_msg}")
      { error: err_msg }
    end
  rescue => e
    duration_ms = defined?(start_time) ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round : 0
    Rails.logger.error("OpenRouter dish_recommendation error [#{e.class}]: #{e.message}")
    record_usage(endpoint: "dish_recommendation", model: model || "unknown", status: "error", duration_ms: duration_ms,
                 error_message: "[#{e.class}] #{e.message}")
    { error: e.message }
  end

# Traduit une notification push (titre + corps) dans plusieurs langues via l'IA.
# Retourne { "fr" => {"title"=>..,"body"=>..}, "en" => {...}, ... }
def translate_push(title:, body:, langs:, model: nil)
  model ||= AppConfig.default_model
  langs = Array(langs).map { |l| l.to_s == "us" ? "en" : l.to_s }
                      .select { |l| %w[fr en de es pt].include?(l) }.uniq
  langs = %w[en] if langs.empty?

  sys = "You translate short mobile push notifications. Keep them concise and punchy, " \
        "preserve emojis, never add extra text."
  usr = "Translate this push notification into these locales: #{langs.join(', ')}.\n" \
        "Return ONLY valid JSON, one object per locale:\n" \
        "{\"fr\":{\"title\":\"...\",\"body\":\"...\"}}\n" \
        "TITLE: #{title}\nBODY: #{body}"

  payload = {
    model:       model,
    max_tokens:  800,
    temperature: 0.2,
    messages:    [{ role: "system", content: sys }, { role: "user", content: usr }]
  }
  response = post("chat/completions", payload)
  data = parse_response(response)
  return {} unless response.success? && !data["error"]

  text = data.dig("choices", 0, "message", "content").to_s
  s = text.index("{"); e = text.rindex("}")
  return {} unless s && e && e > s
  JSON.parse(text[s..e])
rescue => ex
  Rails.logger.error("[translate_push] #{ex.class}: #{ex.message}")
  {}
end

  private

  def post(path, body)
    conn.post(path) do |req|
      req.headers["Authorization"]  = "Bearer #{@api_key}"
      req.headers["Content-Type"]   = "application/json"
      req.headers["HTTP-Referer"]   = "https://dietvision.app"
      req.headers["X-Title"]        = "DietVision"
      req.body = body.to_json
    end
  end

  def conn
    @conn ||= Faraday.new(url: BASE_URL) do |f|
      f.request  :retry, max: 2, exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
      f.options.timeout      = 60   # 60s read timeout (images prennent du temps)
      f.options.open_timeout = 30   # 30s connect timeout
      f.adapter  Faraday.default_adapter
    end
  end

  # Parse manuellement — retourne TOUJOURS un Hash
  def parse_response(response)
    body = response.body
    # Si Faraday a déjà parsé (Hash/Array), on utilise directement
    return body if body.is_a?(Hash)

    parsed = JSON.parse(body.to_s)
    parsed.is_a?(Hash) ? parsed : { "error" => parsed.to_s }
  rescue JSON::ParserError
    raw = body.to_s.first(500)
    Rails.logger.error("OpenRouter JSON parse error (status #{response.status}): #{raw}")
    { "error" => "Réponse non-JSON (#{response.status}): #{raw}" }
  end

  def record_usage(endpoint:, model:, input_tokens: 0, output_tokens: 0, duration_ms: 0, status: "success", error_message: nil)
    cost = estimate_cost(model, input_tokens, output_tokens)
    ApiUsage.create!(
      user:          @user,
      endpoint:      endpoint,
      model:         model,
      input_tokens:  input_tokens,
      output_tokens: output_tokens,
      cost_usd:      cost,
      duration_ms:   duration_ms,
      status:        status,
      error_message: error_message
    )
  end

  def estimate_cost(model, input_tokens, output_tokens)
    # Coûts approximatifs en USD pour 1M tokens
    rates = {
      "google/gemini-2.5-flash"     => { input: 0.30,  output: 2.50 },
      "google/gemini-2.0-flash-001" => { input: 0.075, output: 0.30 },
      "openai/gpt-4o-mini"          => { input: 0.15,  output: 0.60 },
      "openai/gpt-4o"               => { input: 2.50,  output: 10.0 }
    }
    rate = rates[model] || { input: 0.1, output: 0.3 }
    (input_tokens * rate[:input] + output_tokens * rate[:output]) / 1_000_000.0
  end

  def coach_system_prompt(profile, locale, today_context = {})
    lang_instruction = case locale
    when "en" then "Always respond in English."
    when "de" then "Antworte immer auf Deutsch."
    when "es" then "Responde siempre en español."
    when "it" then "Rispondi sempre in italiano."
    when "pt" then "Responda sempre em português."
    when "nl" then "Antwoord altijd in het Nederlands."
    else           "Réponds toujours en français."
    end

    # ── Contexte du jour ──────────────────────────────────────────────────────
    today_section = build_today_context(profile, today_context)

    # ── Profil utilisateur enrichi ────────────────────────────────────────────
    weight      = profile["weight"].to_s
    goal        = profile["goal"].to_s
    diet        = profile["diet"].to_s.presence || "omnivore"
    restrictions = Array(profile["restrictions"]).join(", ").presence || "aucune"
    tdee        = profile["tdee"].to_f.round
    target_p    = profile["targetProtein"].to_i
    target_c    = profile["targetCarbs"].to_i
    target_f    = profile["targetFat"].to_i

    profile_section = <<~PROFILE.strip
      PROFIL UTILISATEUR:
      • Poids: #{weight} kg | Objectif: #{goal} | Régime: #{diet}
      • Restrictions alimentaires: #{restrictions}
      • Objectif calorique: #{tdee} kcal/jour
      • Macros cibles: Protéines #{target_p}g | Glucides #{target_c}g | Lipides #{target_f}g
    PROFILE

    <<~PROMPT.strip
      Tu es DietVision, un coach nutrition et fitness IA expert et personnel.
      Tu as accès aux données réelles de l'utilisateur pour aujourd'hui.
      #{profile_section}
      #{today_section}
      #{lang_instruction}
      Sois concis et pratique. Maximum 4-5 phrases sauf si un plan détaillé est demandé.
      Utilise TOUJOURS les données réelles (calories restantes, protéines, repas) dans tes réponses.
      IMPORTANT: réponds TOUJOURS dans la langue que l'utilisateur utilise pour écrire.
    PROMPT
  end

  def build_today_context(profile, ctx)
    return "" if ctx.blank?

    date          = ctx["date"].presence || Date.today.to_s
    kcal_consumed = ctx["kcal_consumed"].to_i
    kcal_target   = ctx["kcal_target"].to_i.then { |v| v > 0 ? v : profile["tdee"].to_f.round }
    kcal_remaining = ctx["kcal_remaining"].to_i
    protein_g     = ctx["protein_g"].to_i
    protein_target = ctx["protein_target_g"].to_i
    carbs_g       = ctx["carbs_g"].to_i
    carbs_target  = ctx["carbs_target_g"].to_i
    fat_g         = ctx["fat_g"].to_i
    fat_target    = ctx["fat_target_g"].to_i

    meals = Array(ctx["meals"])
    meals_str = if meals.any?
      meals.map { |m| "    • #{m['name']}: #{m['calories']} kcal (P#{m['protein']}g G#{m['carbs']}g L#{m['fat']}g)" }.join("\n")
    else
      "    • Aucun repas enregistré"
    end

    <<~TODAY.strip

      CONTEXTE DU JOUR (#{date}):
      • Calories: #{kcal_consumed} / #{kcal_target} kcal consommées → #{kcal_remaining} kcal restantes
      • Protéines: #{protein_g}g / #{protein_target}g (#{protein_target > 0 ? ((protein_g.to_f / protein_target) * 100).round : 0}%)
      • Glucides: #{carbs_g}g / #{carbs_target}g | Lipides: #{fat_g}g / #{fat_target}g
      • Repas du jour:
      #{meals_str}
    TODAY
  end

  def food_analysis_prompt(locale = "fr")
    lang_note = case locale
    when "en" then "in English"
    when "de" then "auf Deutsch"
    when "es" then "en español"
    when "it" then "in italiano"
    when "pt" then "em português"
    when "nl" then "in het Nederlands"
    else           "en français"
    end

    <<~PROMPT
      Analyse this food photo and return ONLY a JSON object (no markdown, no explanation):
      {
        "name": "food name #{lang_note}",
        "estimatedGrams": integer (estimated visible portion weight in grams),
        "calories": number (for the estimated portion),
        "protein": number in grams,
        "carbs": number in grams,
        "fat": number in grams,
        "fiber": number in grams,
        "vitamins": "key vitamins #{lang_note}",
        "minerals": "key minerals #{lang_note}",
        "healthScore": integer 1-10,
        "tip": "short practical nutrition tip #{lang_note}"
      }
    PROMPT
  end

  def parse_json_response(text)
    cleaned = text&.gsub(/```json|```/, "")&.strip
    JSON.parse(cleaned, symbolize_names: true)
  rescue JSON::ParserError
    { error: "Réponse IA invalide", raw: text }
  end
end
