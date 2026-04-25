class CreateApiUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :api_usages do |t|
      t.references :user,    null: false, foreign_key: true
      t.string  :endpoint,   null: false   # analyze_food | coach_chat
      t.string  :model                     # google/gemini-2.0-flash-001
      t.integer :input_tokens,  default: 0
      t.integer :output_tokens, default: 0
      t.decimal :cost_usd,   precision: 10, scale: 6, default: 0
      t.string  :status,     default: "success"  # success | error
      t.integer :duration_ms

      t.timestamps
    end

    add_index :api_usages, :created_at
    add_index :api_usages, [ :user_id, :created_at ]
  end
end
