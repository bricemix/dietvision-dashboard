class AddLastAutoPushAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :last_auto_push_at, :datetime
  end
end
