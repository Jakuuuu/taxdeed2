# frozen_string_literal: true

# ClearToBidPayload — Single Source of Truth para "qué se filtra y qué no"
# ════════════════════════════════════════════════════════════════════════════
# Aísla en UN SOLO PUNTO AUDITABLE la decisión de qué columnas se emiten para
# cada tier. Cualquier cambio al shape del payload pasa por aquí — los
# controllers nunca arman hashes de parcels manualmente.
#
# Reglas:
#   - clear_to_bid_skeleton: NUNCA address, parcel_id externo, coords,
#     opening_bid, latitude/longitude. Solo lo mínimo para upsell visual.
#   - clear_to_bid_full: payload completo para Premier activo.
#
# Si añades un campo nuevo a Parcel, decide explícitamente en cuál método
# aparece. Por defecto: NO en skeleton.
module ClearToBidPayload
  extend ActiveSupport::Concern

  # Payload "esqueleto" — para Trial, Standard, Pro, sin sub.
  # Recibe una relación YA proyectada con .select(:id, :state, :county, :clear_to_bid_grade).
  # Retorna Array<Hash> con descripción genérica anonimizada.
  def clear_to_bid_skeleton(parcels_relation)
    parcels_relation.map do |p|
      {
        id:    p.id,
        state: p.state,
        county: p.county,
        clear_to_bid_grade: p.clear_to_bid_grade,
        teaser: "Pre-qualified opportunity in #{p.state}"
        # NO incluir: address, parcel_id externo, opening_bid, latitude,
        # longitude, owner_name, ni cualquier dato PII/PII-adjacent.
      }
    end
  end

  # Payload completo — solo para Premier + active.
  # Recibe la relación cargada con includes(:auction).
  def clear_to_bid_full(parcels_relation)
    parcels_relation.map do |p|
      {
        id:                 p.id,
        parcel_id:          p.parcel_id,
        state:              p.state,
        county:             p.county,
        address:            p.address,
        latitude:           p.latitude,
        longitude:          p.longitude,
        polygon_encoded:    p.respond_to?(:polygon_encoded) ? p.polygon_encoded : nil,
        opening_bid:        p.opening_bid,
        clear_to_bid_grade: p.clear_to_bid_grade,
        auction: p.auction && {
          id:        p.auction.id,
          sale_date: p.auction.sale_date
        }
      }
    end
  end
end
