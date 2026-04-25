class AdminUser < ApplicationRecord
  has_secure_password

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  before_save { self.email = email.downcase }

  def superadmin?
    role == "superadmin"
  end
end
