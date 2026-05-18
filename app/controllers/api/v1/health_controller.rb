module Api
  module V1
    class HealthController < BaseController
      skip_authentication :show

      def show
        render json: {
          status:  "ok",
          version: "1.0",
          env:     Rails.env,
          time:    Time.current.iso8601
        }
      end
    end
  end
end
