class AddFitaiDataToUsers < ActiveRecord::Migration[8.0]
  def change
    # FitAI profile (nutrition goal, body measurements, etc.) stored as JSON text
    add_column :users, :fitai_profile, :text
    # Weekly planning (7 DayPlan objects) stored as JSON text
    add_column :users, :planning_data, :text
  end
end
