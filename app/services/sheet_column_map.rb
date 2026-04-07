# frozen_string_literal: true

# SheetColumnMap — Mapeo posicional de columnas del Google Sheet (0-based)
#
# REGLA: Las columnas del Sheet están en un orden fijo.
# Usar SIEMPRE estas constantes — nunca índices numéricos directos.
# Verificar contra el Sheet real si hay dudas.
#
module SheetColumnMap
  # ── IDENTIFICACIÓN Y UBICACIÓN ──────────────────────────────────────────────
  STATE               = 0   # col A  — Estado
  COUNTY              = 1   # col B  — Condado
  PARCEL_ID           = 2   # col C  — Parcel Number
  
  # ⛔ cols D, E, F (3, 4, 5) — Estatus, NOTAS, Comments do VA

  AUCTION_DATE        = 6   # col G  — Auction Date (MM/DD/YYYY)
  MARKET_VALUE        = 7   # col H  — Appraisal (Market Value)
  OPENING_BID         = 8   # col I  — Min. Bid
  ASSESSED_VALUE      = 9   # col J  — Assessed Value
  LOT_AREA_ACRES      = 10  # col K  — Lot Area (acres)
  SQFT_LOT            = 11  # col L  — Lot Area sqft
  SQFT_LIVING         = 12  # col M  — Lot Area Home (sqft)
  
  # ⛔ cols N, O (13, 14) — Hab, Bd

  MINIMUM_LOT_SIZE    = 15  # col P  — Minimum Lot Size (texto)
  ZONING              = 16  # col Q  — Zoning Code
  JURISDICTION        = 17  # col R  — Jurisdiction
  LAND_USE            = 18  # col S  — Type Lot / Land Use
  OWNER_NAME          = 19  # col T  — Owner Name
  OWNER_MAIL_ADDRESS  = 20  # col U  — Mail Address (NO exponer en API pública)
  
  PROPERTY_ADDRESS    = 21  # col V  — Property Address (física)
  ADDRESS             = 21  # (Mantiene retrocompatibilidad mapeando a Property Address)
  
  ZIP                 = 22  # col W  — Zip Code
  CITY                = 23  # col X  — Localidad / Ciudad
  
  LEGAL_DESCRIPTION   = 24  # col Y  — Legal Description
  CRIME_LEVEL         = 25  # col Z  — Crime level ("Low" | "Moderate" | "High")
  HOMESTEAD_FLAG      = 26  # col AA — Homestead x Investor ("Homestead" | "Investor")
  REGRID_URL          = 27  # col AB — Regrid Link
  GIS_IMAGE_URL       = 28  # col AC — GIS Map Image URL
  GOOGLE_MAPS_URL     = 29  # col AD — Google Maps URL
  ELECTRIC            = 30  # col AE — Electric ("yes" | "no")
  WATER               = 31  # col AF — Water ("yes" | "no")
  SEWER               = 32  # col AG — Sewer ("yes" | "no")
  LOT_SHAPE           = 33  # col AH — Forma Terreno ("Flat" etc.)
  
  # ⛔ col AI (34) — NEIGHBOR address
  COORDINATES_RAW     = 35  # col AJ — Coordinates Lat x Log (formato: "30.452145, -87.270564")

  WETLANDS_RAW        = 36  # col AK — Wetlands ("yes" | "no" → boolean)
  FEMA_NOTES          = 37  # col AL — Comments on FEMA image
  FEMA_URL            = 38  # col AM — Link FEMA
  FEMA_RISK_LEVEL     = 39  # col AN — Risk factor/FEMA Image label
  PROPERTY_IMAGE_URL  = 40  # col AO — Property Image URL
  
  # ⛔ col AP (41) — Zillow (metadata / string)
  
  HOA                 = 42  # col AQ — POA/HOA ("yes" | "no")

  # ⛔ cols AR→BO (43→66) — Zillow comps (Links, Price, Sqft, Acres, etc.)

  ESTIMATED_SALE_VALUE = 67 # col BP — Estimate Sale (sites)

  # ⛔ cols BQ→BW (68→74) — Cálculos duplicados y estimaciones extra

  CLERK_URL           = 75  # col BX — Clerk of Courts URL
  TAX_COLLECTOR_URL   = 76  # col BY — Tax Collector URL

  # ⛔ cols BZ→CA (77→78) — Realforeclose, Zoning Ordinances

  # ── COLUMNAS IGNORADAS (documentadas para referencia) ────────────────────────
  IGNORED_INTERNAL = [3, 4, 5, 13, 14, 34, 41, 77, 78].freeze  # 35 (AJ) ahora es COORDINATES_RAW
  IGNORED_ZILLOW   = (43..66).to_a.freeze
  IGNORED_CALCS    = (68..74).to_a.freeze
end
