class AddErrorMessageToApiUsages < ActiveRecord::Migration[8.0]
  def change
    add_column :api_usages, :error_message, :text
  end
end
