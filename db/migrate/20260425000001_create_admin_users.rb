class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_users do |t|
      t.string :name, null: false
      t.string :email, null: false, index: { unique: true }
      t.string :password_digest, null: false
      t.string :role, default: "admin"   # admin | superadmin
      t.datetime :last_login_at

      t.timestamps
    end
  end
end
