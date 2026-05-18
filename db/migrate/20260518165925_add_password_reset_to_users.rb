class AddPasswordResetToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :password_reset_token,    :string, limit: 6
    add_column :users, :password_reset_sent_at,  :datetime
  end
end
