# frozen_string_literal: true

# SheetColumnMap — Mapeo posicional de columnas del Google Sheet (0-based)
#
# REGLA: Las columnas del Sheet están en un orden fijo.
# Usar SIEMPRE estas constantes — nunca índices numéricos directos.
# Verificar contra el Sheet real si hay dudas.
#
module SheetColumnMap
  # ── IDENTIFICACIÓN Y UBICACIÓN ──────────────────────────────────────────────
  COUNTY              = 0   # col A  — Condado
  STATE               = 1   # col B  — Estado
  ADDRESS             = 2   # col C  — Direccion (dirección del remate)
  OPENING_BID         = 3   # col D  — Min. Bid
  PARCEL_ID           = 4   # col E  — Parcel Number (clave de upsert)

  # ⛔ col F (5)  = Estado de análisis  → IGNORAR (referencia interna)
  # ⛔ col G (6)  = NOTAS               → IGNORAR (referencia interna)
  # ⛔ col H (7)  = Comments do V.A     → IGNORAR (referencia interna)

  AUCTION_DATE        = 8   # col I  — Auction Date (MM/DD/YYYY)
  MARKET_VALUE        = 9   # col J  — Appraisal (Market Value)
  ASSESSED_VALUE      = 10  # col K  — Assessed Value
  LOT_AREA_ACRES      = 11  # col L  — Lot Area (acres)
  SQFT_LOT            = 12  # col M  — Lot Area sqft
  SQFT_LIVING         = 13  # col N  — Lot Area Home (sqft living area)
  MINIMUM_LOT_SIZE    = 14  # col O  — Minimum Lot Size (texto)
  ZONING              = 15  # col P  — Zoning Code
  JURISDICTION        = 16  # col Q  — Jurisdiction
  LAND_USE            = 17  # col R  — Type Lot / Land Use
  OWNER_NAME          = 18  # col S  — Owner Name
  OWNER_MAIL_ADDRESS  = 19  # col T  — Mail Address (NO exponer en API pública)
  PROPERTY_ADDRESS    = 20  # col U  — Property Address (dirección física del predio)
  ZIP                 = 21  # col V  — Zip Code
  LEGAL_DESCRIPTION   = 22  # col W  — Legal Description
  CRIME_LEVEL         = 23  # col X  — Crime level ("Low" | "Moderate" | "High")
  HOMESTEAD_FLAG      = 24  # col Y  — Homestead x Investor ("Homestead" | "Investor")
  REGRID_URL          = 25  # col Z  — Regrid Link
  GIS_IMAGE_URL       = 26  # col AA — GIS Map Image URL
  GOOGLE_MAPS_URL     = 27  # col AB — Google Maps URL
  ELECTRIC            = 28  # col AC — Electric ("yes" | "no")
  WATER               = 29  # col AD — Water ("yes" | "no")
  SEWER               = 30  # col AE — Sewer ("yes" | "no")
  LOT_SHAPE           = 31  # col AF — Forma Terreno ("Flat" etc.)
  WETLANDS_RAW        = 32  # col AG — Wetlands ("yes" | "no" → boolean)
  FEMA_NOTES          = 33  # col AH — Comments on FEMA image
  FEMA_RISK_LEVEL     = 34  # col AI — Risk factor / FEMA Image label
  FEMA_URL            = 35  # col AJ — FEMA Link
  PROPERTY_IMAGE_URL  = 36  # col AK — Property Image URL

  # ⛔ col AL (37) — buffer sin uso conocido (entre AK y AM)

  HOA                 = 38  # col AM — POA/HOA ("yes" | "no")

  # ⛔ cols AN (39)            — posible buffer adicional

  # ⛔ cols AO→BL (40→63)     — 4x sets Zillow comps → IGNORAR (referencia interna)

  ESTIMATED_SALE_VALUE = 64  # col BM — Estimate Sale (sites)

  # ⛔ cols BN→BS (65→70)     — cálculos duplicados (16%, MaxBid, etc.) → calcular al vuelo en UI

  CLERK_URL           = 71  # col BT — Clerk of Courts URL
  TAX_COLLECTOR_URL   = 72  # col BU — Tax Collector URL

  # ── COLUMNAS IGNORADAS (documentadas para referencia) ────────────────────────
  IGNORED_INTERNAL = [5, 6, 7].freeze          # Estado análisis, NOTAS, Comments V.A
  IGNORED_BUFFER   = [37, 39].freeze           # Buffers sin uso
  IGNORED_ZILLOW   = (40..63).to_a.freeze      # 4x sets Zillow comps
  IGNORED_CALCS    = (65..70).to_a.freeze      # Cálculos duplicados
end
