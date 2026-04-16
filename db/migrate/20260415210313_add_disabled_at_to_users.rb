class AddDisabledAtToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :disabled_at, :datetime
  end
end
