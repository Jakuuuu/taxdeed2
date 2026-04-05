# frozen_string_literal: true

# Active Storage tables are created via rails active_storage:install
# This migration removes the unused download_url column from reports
# (PDFs now stored in Active Storage instead of external URL)
class AddActiveStorageToReports < ActiveRecord::Migration[7.2]
  def change
    # Remove external download_url — PDFs now stored in Active Storage
    # (only remove if it exists, in case migration is re-run)
    remove_column :reports, :download_url, :string, if_exists: true
    remove_column :reports, :provider_ref, :string, if_exists: true
  end
end
