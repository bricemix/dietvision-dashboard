class PromoCodeRedemption < ApplicationRecord
  belongs_to :user
  belongs_to :promo_code
  belongs_to :payment, optional: true
end
