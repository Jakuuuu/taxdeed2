# frozen_string_literal: true

# Registro de exportaciones (CSV/XLSX) hechas por el usuario.
# Útil para auditoría y enforcement de exports_limit.
class ExportLog < ApplicationRecord
  FORMATS = %w[csv xlsx].freeze

  belongs_to :user

  validates :parcels_exported, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :export_format, inclusion: { in: FORMATS }
end
