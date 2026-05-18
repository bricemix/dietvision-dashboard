class OpenrouterService
  BASE_URL = "https://openrouter.ai/api/v1/"  # trailing slash obligatoire pour Faraday

  def initialize(user:)
    @user   = user
    @api_key = AppConfig.openrouter_api_key
  end

  # Analyse une image alimentaire (base64 JPEG)
  def analyze_food(base64_image, model: nil, locale: "fr")
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
              text: food_analysis_prompt(locale)
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
  def coach_chat(messages, profile:, model: nil, locale: "fr")
    model ||= AppConfig.default_model
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    system_msg = {
      role: "system",
      content: coach_system_prompt(profile, locale)
    }

    payload = {
      model: model,
      max_tokens: 400,
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
      "google/gemini-2.0-flash-001" => { input: 0.075, output: 0.30 },
      "openai/gpt-4o-mini"          => { input: 0.15,  output: 0.60 },
      "openai/gpt-4o"               => { input: 2.50,  output: 10.0 }
    }
    rate = rates[model] || { input: 0.1, output: 0.3 }
    (input_tokens * rate[:input] + output_tokens * rate[:output]) / 1_000_000.0
  end

  def coach_system_prompt(profile, locale)
    lang_instruction = case locale
    when "en" then "Always respond in English."
    when "de" then "Antworte immer auf Deutsch."
    when "es" then "Responde siempre en español."
    when "it" then "Rispondi sempre in italiano."
    when "pt" then "Responda sempre em português."
    when "nl" then "Antwoord altijd in het Nederlands."
    else           "Réponds toujours en français."
    end

    "You are DietVision, an expert nutrition and fitness coach. " \
    "User profile: #{profile.to_json}. " \
    "#{lang_instruction} " \
    "Be concise and practical. Max 3-4 sentences. " \
    "IMPORTANT: always reply in the SAME language the user writes in — " \
    "if the user writes in English reply in English, if in French reply in French, etc."
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
