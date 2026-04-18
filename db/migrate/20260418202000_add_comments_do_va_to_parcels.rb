# frozen_string_literal: true

class AddCommentsDoVaToParcels < ActiveRecord::Migration[7.2]
  def change
    add_column :parcels, :comments_do_va, :text
  end
end
