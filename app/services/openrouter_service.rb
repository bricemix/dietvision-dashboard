class OpenrouterService
  BASE_URL = "https://openrouter.ai/api/v1"

  def initialize(user:)
    @user   = user
    @api_key = AppConfig.openrouter_api_key
  end

  # Analyse une image alimentaire (base64 JPEG)
  def analyze_food(base64_image, model: nil)
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
              text: food_analysis_prompt
            }
          ]
        }
      ]
    }

    response = post("/chat/completions", payload)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    if response.success?
      data   = response.body
      text   = data.dig("choices", 0, "message", "content")
      usage  = data["usage"] || {}
      record_usage(endpoint: "analyze_food", model: model,
                   input_tokens: usage["prompt_tokens"].to_i,
                   output_tokens: usage["completion_tokens"].to_i,
                   duration_ms: duration_ms, status: "success")
      parse_json_response(text)
    else
      record_usage(endpoint: "analyze_food", model: model, status: "error", duration_ms: duration_ms)
      { error: "Analyse échouée (#{response.status})" }
    end
  rescue => e
    record_usage(endpoint: "analyze_food", model: model || "unknown", status: "error")
    { error: e.message }
  end

  # Coach IA — messages est un array [{role:, content:}]
  def coach_chat(messages, profile:, model: nil)
    model ||= AppConfig.default_model
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    system_msg = {
      role: "system",
      content: "Tu es DietVision, un coach nutrition et fitness expert. " \
               "Profil utilisateur: #{profile.to_json}. " \
               "Tu réponds en français, de façon concise et pratique. Max 3-4 phrases."
    }

    payload = {
      model: model,
      max_tokens: 400,
      messages: [ system_msg ] + messages
    }

    response = post("/chat/completions", payload)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    if response.success?
      data   = response.body
      text   = data.dig("choices", 0, "message", "content")
      usage  = data["usage"] || {}
      record_usage(endpoint: "coach_chat", model: model,
                   input_tokens: usage["prompt_tokens"].to_i,
                   output_tokens: usage["completion_tokens"].to_i,
                   duration_ms: duration_ms, status: "success")
      { content: text }
    else
      record_usage(endpoint: "coach_chat", model: model, status: "error", duration_ms: duration_ms)
      { error: "Coach indisponible (#{response.status})" }
    end
  rescue => e
    record_usage(endpoint: "coach_chat", model: model || "unknown", status: "error")
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
      f.request  :retry, max: 2
      f.response :json
      f.adapter  Faraday.default_adapter
    end
  end

  def record_usage(endpoint:, model:, input_tokens: 0, output_tokens: 0, duration_ms: 0, status: "success")
    cost = estimate_cost(model, input_tokens, output_tokens)
    ApiUsage.create!(
      user:          @user,
      endpoint:      endpoint,
      model:         model,
      input_tokens:  input_tokens,
      output_tokens: output_tokens,
      cost_usd:      cost,
      duration_ms:   duration_ms,
      status:        status
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

  def food_analysis_prompt
    <<~PROMPT
      Analyse this food photo and return ONLY a JSON object (no markdown, no explanation):
      {
        "name": "food name in French",
        "estimatedGrams": integer (estimated visible portion weight),
        "calories": number (for the estimated portion),
        "protein": number in grams,
        "carbs": number in grams,
        "fat": number in grams,
        "fiber": number in grams,
        "vitamins": "key vitamins",
        "minerals": "key minerals",
        "healthScore": integer 1-10,
        "tip": "short nutrition tip in French"
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
