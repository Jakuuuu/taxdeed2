# frozen_string_literal: true

# Agrega campos necesarios para la gestión interna de Title Searches por el equipo admin.
#   admin_notes:          notas internas del equipo (no visibles al usuario)
#   datatrace_order_ref:  referencia del pedido a DataTrace (ej: 'TSR_Current Owner_509 W Blount St')
class AddAdminFieldsToReports < ActiveRecord::Migration[7.2]
  def change
    add_column :reports, :admin_notes, :text
    add_column :reports, :datatrace_order_ref, :string, limit: 200
  end
end
