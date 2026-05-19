class AddSecurityColumns < ActiveRecord::Migration[8.0]
  def change
    # BUG-01 : compteur de tentatives de vérification email (brute-force OTP)
    add_column :users, :email_verification_attempts, :integer, default: 0, null: false

    # BUG-02 : compteur de tentatives de reset mot de passe
    add_column :users, :password_reset_attempts, :integer, default: 0, null: false

    # BUG-07 : lockout admin après N échecs de connexion
    add_column :admin_users, :failed_login_count, :integer, default: 0, null: false
    add_column :admin_users, :locked_until,       :datetime

    # Index pour les lookups de lockout fréquents
    add_index :admin_users, :locked_until
  end
end
