class SendPromoCodeUsageReportJob < ApplicationJob
  queue_as :default

  def perform
    PromoCode.where.not(notification_emails_json: [nil, "[]", ""]).find_each do |promo_code|
      emails = promo_code.notification_emails
      next if emails.blank?

      since = 24.hours.ago
      redemptions_today = promo_code.promo_code_redemptions.where(created_at: since..Time.current)

      PromoCodeMailer.daily_usage_report(
        promo_code:   promo_code,
        emails:       emails,
        today_count:  redemptions_today.count,
        today_unique: redemptions_today.distinct.count(:user_id),
        total_uses:   promo_code.uses_count,
        total_unique: promo_code.promo_code_redemptions.distinct.count(:user_id)
      ).deliver_now
    rescue => e
      Rails.logger.error("SendPromoCodeUsageReportJob error for #{promo_code.code}: #{e.message}")
    end
  end
end
