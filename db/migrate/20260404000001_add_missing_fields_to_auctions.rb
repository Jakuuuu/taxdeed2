# frozen_string_literal: true

class AddMissingFieldsToAuctions < ActiveRecord::Migration[7.2]
  def change
    add_column :auctions, :registration_opens, :date,   if_not_exists: true
    add_column :auctions, :end_date,           :date,   if_not_exists: true
    add_column :auctions, :source_url,         :string, limit: 500, if_not_exists: true
  end
end
