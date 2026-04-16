# frozen_string_literal: true

# AdminAuditLog — registro inmutable de acciones admin sobre cuentas de usuario.
#
# Columnas:
#   admin_user_id  → quién ejecutó la acción (FK → users)
#   target_user_id → sobre quién se ejecutó (FK → users)
#   action         → toggle_admin | reset_usage | cancel_subscription
#   details        → descripción legible del cambio
#
class AdminAuditLog < ApplicationRecord
  belongs_to :admin_user,  class_name: "User"
  belongs_to :target_user, class_name: "User"

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # Convenience builder — call from controller after each admin action
  def self.log!(admin:, target:, action:, details:)
    create!(
      admin_user:  admin,
      target_user: target,
      action:      action,
      details:     details
    )
  end
end
