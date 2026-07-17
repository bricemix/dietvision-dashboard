class AddNotificationEmailsToPromoCodes < ActiveRecord::Migration[8.0]
  def change
    add_column :promo_codes, :notification_emails_json, :text, default: "[]"
  end
end
