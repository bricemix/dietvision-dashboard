module ApplicationHelper
  include Pagy::Frontend

  # Nav link avec icône SVG (block)
  def nav_link_icon(path, label, &block)
    active = current_page?(path) || request.path.start_with?(path.sub(/\/$/, ""))
    css    = "nav-link#{active ? " active" : ""}"
    link_to path, class: css do
      concat capture(&block)
      concat content_tag(:span, label)
    end
  end

  # Badge de statut
  def status_badge(status)
    content_tag :span, status.to_s, class: "badge badge-#{status}"
  end

  # Formatage montant en dollars (centimes → $)
  # Les montants sont stockés en centimes entiers (ex: 999 = $9.99)
  def format_dollars(amount)
    dollars = amount.to_i / 100.0
    "$#{"%.2f" % dollars}"
  end

  # Alias pour compatibilité avec les vues existantes
  alias_method :format_ariary, :format_dollars
  alias_method :format_xof,    :format_dollars

  # Formatage coût USD précis (pour les logs de coût API, 4 décimales)
  def format_usd(amount)
    "$#{"%.4f" % amount.to_f}"
  end

  # Label opérateur de paiement
  def operator_label(provider)
    {
      "mvola"        => "MVola",
      "orange_money" => "Orange Money",
      "airtel_money" => "Airtel Money",
      "cinetpay"     => "CinetPay",
      "mtn"          => "MTN",
      "orange"       => "Orange",
      "wave"         => "Wave"
    }[provider.to_s] || provider.to_s.humanize
  end

  # Couleur badge opérateur
  def operator_badge(provider)
    color = case provider.to_s
            when "mvola"        then "background:#e84393;color:#fff"
            when "orange_money" then "background:#ff7900;color:#fff"
            when "airtel_money" then "background:#e40000;color:#fff"
            else "background:#374151;color:#9ca3af"
            end
    content_tag :span, operator_label(provider),
                style: "#{color};font-size:11px;font-weight:600;padding:2px 8px;border-radius:100px"
  end
end
