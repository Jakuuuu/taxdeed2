# frozen_string_literal: true

# SheetColumnMap — Mapeo posicional de columnas del Google Sheet (0-based)
#
# REGLA: Las columnas del Sheet están en un orden fijo.
# Usar SIEMPRE estas constantes — nunca índices numéricos directos.
# Verificar contra el Sheet real si hay dudas.
#
# ⚠️ ACTUALIZADO 2026-04-18: Se insertó "Sale Venue" en col C (pos 2).
#    Todas las posiciones desde la antigua pos 2 se corrieron +1.
#    Verificado contra HEADER MAP real del Sheet "Propiedades1".
#
module SheetColumnMap
  # ── IDENTIFICACIÓN Y UBICACIÓN ──────────────────────────────────────────────
  STATE               = 0   # col A  — Estado
  COUNTY              = 1   # col B  — Condado
  SALE_VENUE          = 2   # col C  — Sale Venue (NUEVA — 2026-04-18)
  PARCEL_ID           = 3   # col D  — Parcel Number

  # ⛔ cols E, F, G (4, 5, 6) — Estatus, NOTAS, Comments do VA

  AUCTION_DATE        = 7   # col H  — Auction Date (MM/DD/YYYY)
  MARKET_VALUE        = 8   # col I  — Appraisal (Market Value)
  OPENING_BID         = 9   # col J  — Min. Bid
  ASSESSED_VALUE      = 10  # col K  — Assessed Value
  LOT_AREA_ACRES      = 11  # col L  — Lot Area (acres)
  SQFT_LOT            = 12  # col M  — Lot Area sqft
  SQFT_LIVING         = 13  # col N  — Lot Area Home (sqft)

  # ⛔ cols O, P (14, 15) — Hab, Bd

  MINIMUM_LOT_SIZE    = 16  # col Q  — Minimum Lot Size (texto)
  ZONING              = 17  # col R  — Zoning Code
  JURISDICTION        = 18  # col S  — Jurisdiction
  LAND_USE            = 19  # col T  — Type Lot / Land Use
  OWNER_NAME          = 20  # col U  — Owner Name
  OWNER_MAIL_ADDRESS  = 21  # col V  — Mail Address (NO exponer en API pública)

  PROPERTY_ADDRESS    = 22  # col W  — Property Address (física)
  ADDRESS             = 22  # (Mantiene retrocompatibilidad mapeando a Property Address)

  ZIP                 = 23  # col X  — Zip Code
  CITY                = 24  # col Y  — Localidad / Ciudad

  LEGAL_DESCRIPTION   = 25  # col Z  — Legal Description
  CRIME_LEVEL         = 26  # col AA — Crime level ("Low" | "Moderate" | "High")
  HOMESTEAD_FLAG      = 27  # col AB — Homestead x Investor ("Homestead" | "Investor")
  REGRID_URL          = 28  # col AC — Regrid Link
  GIS_IMAGE_URL       = 29  # col AD — GIS Map Image URL
  GOOGLE_MAPS_URL     = 30  # col AE — Google Maps URL
  ELECTRIC            = 31  # col AF — Electric ("yes" | "no")
  WATER               = 32  # col AG — Water ("yes" | "no")
  SEWER               = 33  # col AH — Sewer ("yes" | "no")
  LOT_SHAPE           = 34  # col AI — Forma Terreno ("Flat" etc.)

  # ⛔ col AJ (35) — NEIGHBOR address
  COORDINATES_RAW     = 36  # col AK — Coordinates Lat x Log (formato: "30.452145, -87.270564")

  WETLANDS_RAW        = 37  # col AL — Wetlands ("yes" | "no" → boolean)
  FEMA_NOTES          = 38  # col AM — Comments on FEMA image
  FEMA_URL            = 39  # col AN — Link FEMA
  FEMA_RISK_LEVEL     = 40  # col AO — Risk factor/FEMA Image label
  PROPERTY_IMAGE_URL  = 41  # col AP — Property Image URL

  # ⛔ col AQ (42) — Zillow (metadata / string)

  HOA                 = 43  # col AR — POA/HOA ("yes" | "no")

  # ⛔ cols AS→BP (44→67) — Zillow comps (Links, Price, Sqft, Acres, etc.)

  ESTIMATED_SALE_VALUE = 68 # col BQ — Estimate Sale (sites)

  # ⛔ cols BR→BX (69→75) — Cálculos duplicados y estimaciones extra

  CLERK_URL           = 76  # col BY — Clerk of Courts URL
  TAX_COLLECTOR_URL   = 77  # col BZ — Tax Collector URL

  # ⛔ cols CA→CB (78→79) — Realforeclose, Zoning Ordinances

  # ── COLUMNAS IGNORADAS (documentadas para referencia) ────────────────────────
  IGNORED_INTERNAL = [4, 5, 6, 14, 15, 35, 42, 78, 79].freeze
  IGNORED_ZILLOW   = (44..67).to_a.freeze
  IGNORED_CALCS    = (69..75).to_a.freeze
end
