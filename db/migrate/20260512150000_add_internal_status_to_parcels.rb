# frozen_string_literal: true

# Migración: añade internal_status a parcels
#
# Propósito: almacenar el valor de la columna "Estatus" (col E, índice 4) del
# Google Sheet de propiedades. El equipo de datos lo usa para indicar si una
# propiedad aún está disponible para subasta o fue redimida.
#
# Acceso: Solo usuarios Premier (plan "premier" + status "active") o Admin.
#         El campo se sirve exclusivamente en el payload full del ClearToBidController.
#         Los usuarios Standard/Pro/Trial NUNCA lo reciben.
#
# Poblado automáticamente: en el próximo sync tras el deploy.
#
class AddInternalStatusToParcels < ActiveRecord::Migration[7.2]
  def change
    add_column :parcels, :internal_status, :string, limit: 120, null: true

    # Comentario SQL para auditoría en pgAdmin / Render DB explorer
    execute <<~SQL
      COMMENT ON COLUMN parcels.internal_status IS
        'Estatus operativo de la propiedad (col E del Sheet). Ej: Disponible, Redimida. Visible solo a usuarios Premier/Admin.';
    SQL
  end
end
