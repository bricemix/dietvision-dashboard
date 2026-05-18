class CreateAdminLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_logs do |t|
      t.integer :admin_user_id
      t.string  :action,        null: false
      t.string  :resource_type
      t.integer :resource_id
      t.text    :details_json
      t.string  :ip_address
      t.timestamps
    end
    add_index :admin_logs, :admin_user_id
    add_index :admin_logs, :created_at
    add_index :admin_logs, %i[resource_type resource_id]
  end
end
