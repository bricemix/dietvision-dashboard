module Api
  module V1
    class ChatController < BaseController
      LOAD_LIMIT = 100

      # GET /api/v1/chat/history
      def index
        scope = current_user.chat_messages.ordered
        scope = scope.where("id < ?", params[:before_id].to_i) if params[:before_id].present?
        msgs  = scope.last(LOAD_LIMIT)
        render json: msgs.map { |m|
          { id: m.id, role: m.role, content: m.content, created_at: m.created_at }
        }
      end

      # POST /api/v1/chat/messages
      # Body: { messages: [{ role: "user", content: "..." }, { role: "assistant", content: "..." }] }
      def create
        list = params[:messages]
        return render json: { error: "messages required" }, status: :bad_request if list.blank?

        saved = 0
        ActiveRecord::Base.transaction do
          list.each do |m|
            role    = m[:role].to_s
            content = m[:content].to_s.strip
            next unless %w[user assistant].include?(role) && content.present?
            current_user.chat_messages.create!(role: role, content: content)
            saved += 1
          end
        end
        render json: { saved: saved }, status: :created
      rescue => e
        Rails.logger.error("ChatController#create error: #{e.message}")
        render json: { error: "Server error" }, status: :internal_server_error
      end

      # DELETE /api/v1/chat/history
      def destroy
        current_user.chat_messages.delete_all
        head :ok
      end
    end
  end
end
