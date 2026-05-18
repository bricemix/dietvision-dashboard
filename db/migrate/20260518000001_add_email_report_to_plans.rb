class AddEmailReportToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :email_report_frequency, :string, default: 'never', null: false
    add_column :plans, :email_report_day, :string, default: 'monday'  # pour weekly: jour de la semaine
  end
end
