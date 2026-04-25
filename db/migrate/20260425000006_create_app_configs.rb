class CreateAppConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :app_configs do |t|
      t.string :key,   null: false, index: { unique: true }
      t.text   :value
      t.string :description

      t.timestamps
    end
  end
end
