module Api
  module V1
    class PromoCodesController < BaseController
      # POST /api/v1/promo_codes/validate
      def validate
        code = PromoCode.find_by(code: params[:code]&.upcase&.strip)

        if code&.valid_now?
          render json: {
            valid:          true,
            code:           code.code,
            discount_type:  code.discount_type,
            discount_value: code.discount_value.to_f,
            discount_label: code.discount_label
          }
        else
          render json: { valid: false, error: "Code invalide ou expiré" },
                 status: :unprocessable_entity
        end
      end
    end
  end
end
