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

  # Formatage montant XOF
  def format_xof(amount)
    parts = amount.to_i.to_s.chars.reverse.each_slice(3).map(&:join).join(" ").reverse
    "#{parts} XOF"
  end

  # Formatage coût USD
  def format_usd(amount)
    "$#{"%.4f" % amount.to_f}"
  end
end
