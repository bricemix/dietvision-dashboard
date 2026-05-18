class AddTrialFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :trial_ends_at, :datetime
    add_column :users, :had_trial,     :boolean, default: false, null: false
    add_index  :users, :trial_ends_at
  end
end
