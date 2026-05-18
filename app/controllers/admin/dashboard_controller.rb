module Admin
  class DashboardController < BaseController
    def index
      # ── Utilisateurs ──────────────────────────────────────────
      @total_users      = User.count
      @premium_users    = User.where(plan: "premium").count
      @free_users       = User.where(plan: "free").count
      @trial_users      = User.in_trial.count
      @new_users_month  = User.new_this_month.count

      # Actifs (via appels API)
      @active_today     = ApiUsage.select(:user_id).distinct.today.count
      @active_month     = ApiUsage.select(:user_id).distinct.this_month.count

      # ── Revenus ───────────────────────────────────────────────
      @total_revenue    = Payment.successful.sum(:amount)
      @revenue_month    = Payment.successful.this_month.sum(:amount)
      @pending_payments = Payment.pending.count

      # Revenus par opérateur ce mois
      @revenue_by_operator = Payment.successful.this_month
                                    .group(:provider).sum(:amount)

      # ── Conversion essai → payant ─────────────────────────────
      @total_had_trial = User.where(had_trial: true).count
      @converted       = User.where(had_trial: true, plan: "premium").count
      @conversion_rate = @total_had_trial > 0 ? (@converted.to_f / @total_had_trial * 100).round(1) : 0.0

      # ── API ───────────────────────────────────────────────────
      @api_calls_today  = ApiUsage.today.count
      @api_calls_month  = ApiUsage.this_month.count
      @api_cost_month   = ApiUsage.this_month.total_cost.round(4)

      # ── Graphique 30 jours (inscriptions) ────────────────────
      raw = User.group_by_day(:created_at, last: 30, time_zone: "UTC").count
      @chart_labels  = raw.keys.map  { |d| d.strftime("%-d/%-m") }.to_json.html_safe
      @chart_values  = raw.values.to_json.html_safe

      # ── Tableaux récents ──────────────────────────────────────
      @recent_users    = User.order(created_at: :desc).limit(5)
      @recent_payments = Payment.successful.order(paid_at: :desc).limit(5).includes(:user, :subscription)
    end
  end
end
