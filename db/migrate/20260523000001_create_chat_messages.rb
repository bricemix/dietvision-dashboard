class CreateChatMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :chat_messages do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :role,    null: false  # user | assistant
      t.text   :content, null: false
      t.timestamps
    end
    add_index :chat_messages, [:user_id, :created_at]
  end
end
