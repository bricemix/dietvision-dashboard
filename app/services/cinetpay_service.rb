class CinetpayService
  BASE_URL = "https://api-checkout.cinetpay.com/v2"

  def initialize
    @api_key = AppConfig.cinetpay_api_key
    @site_id = AppConfig.cinetpay_site_id
  end

  # Initie un paiement Mobile Money
  # Retourne { payment_url: "...", transaction_id: "..." } ou { error: "..." }
  def initiate_payment(amount:, transaction_id:, description:, phone:, name:, notify_url:, return_url:)
    payload = {
      apikey:          @api_key,
      site_id:         @site_id,
      transaction_id:  transaction_id,
      amount:          amount.to_i,
      currency:        "XOF",
      description:     description,
      notify_url:      notify_url,
      return_url:      return_url,
      customer_name:   name,
      customer_phone_number: phone,
      channels:        "MOBILE_MONEY",
      metadata:        transaction_id
    }

    response = post("/payment", payload)

    if response.success?
      data = response.body
      if data["code"] == "201"
        {
          payment_url:    data.dig("data", "payment_url"),
          transaction_id: transaction_id
        }
      else
        { error: data["message"] || "Erreur CinetPay (#{data['code']})" }
      end
    else
      { error: "Erreur réseau (#{response.status})" }
    end
  rescue => e
    { error: e.message }
  end

  # Vérifie le statut d'un paiement via webhook ou polling
  def check_payment(transaction_id)
    payload = {
      apikey:         @api_key,
      site_id:        @site_id,
      transaction_id: transaction_id
    }

    response = post("/payment/check", payload)

    if response.success?
      data = response.body
      status_code = data.dig("data", "status")
      {
        status:       map_status(status_code),
        provider_ref: data.dig("data", "operator_id"),
        raw:          data
      }
    else
      { error: "Vérification échouée (#{response.status})" }
    end
  rescue => e
    { error: e.message }
  end

  private

  def map_status(cinetpay_status)
    case cinetpay_status
    when "ACCEPTED" then "success"
    when "REFUSED"  then "failed"
    when "PENDING"  then "pending"
    else "pending"
    end
  end

  def post(path, body)
    conn.post(path) do |req|
      req.headers["Content-Type"] = "application/json"
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
end
