# frozen_string_literal: true

# SheetColumnMap — Mapeo posicional de columnas del Google Sheet (0-based)
#
# REGLA: Las columnas del Sheet están en un orden fijo.
# Usar SIEMPRE estas constantes — nunca índices numéricos directos.
# Verificar contra el Sheet real si hay dudas.
#
# ⚠️ ACTUALIZADO 2026-04-24: Remapeo estructural completo.
#    Sheet "Propiedades1" = 82 columnas (A→CD, pos 0→81).
#    Cambios:
#      - Comments do VA (6), Regrid Link (28), GIS Map Image (29) → IGNORADAS
#      - Price Estimate (72), Max Bid 30% (74), Max Bid 35% (75),
#        Technical analysis (76), Property Apraisal Page (77) → NUEVAS
#      - Clerk of Courts: 79→78, Tax Collector: 80→79
#
module SheetColumnMap
  # ── IDENTIFICACIÓN Y UBICACIÓN ──────────────────────────────────────────────
  STATE               = 0   # col A  — Estado
  COUNTY              = 1   # col B  — Condado
  SALE_VENUE          = 2   # col C  — Sale Venue
  PARCEL_ID           = 3   # col D  — Parcel Number

  # ⛔ col E (4) — Estatus (uso interno, IGNORADA)
  # ⛔ col F (5) — NOTAS (uso interno, IGNORADA)
  # ⛔ col G (6) — Comments do VA (IGNORADA desde 2026-04-24)

  # ── VALUACIÓN Y SUBASTA ──────────────────────────────────────────────────────
  AUCTION_DATE        = 7   # col H  — Auction Date (MM/DD/YYYY)
  MARKET_VALUE        = 8   # col I  — Appraisal (Market Value)
  OPENING_BID         = 9   # col J  — Min. Bid
  ASSESSED_VALUE      = 10  # col K  — Assessed Value

  # ── DIMENSIONES ──────────────────────────────────────────────────────────────
  LOT_AREA_ACRES      = 11  # col L  — Lot Area (acres)
  SQFT_LOT            = 12  # col M  — Lot Area sqft
  SQFT_LIVING         = 13  # col N  — Lot Area Home (sqft)
  HAB                 = 14  # col O  — "Habitaciones" → bedrooms (entero)
  BD                  = 15  # col P  — "BD" → bathrooms (decimal(3,1))

  # ── TERRENO Y ZONING ────────────────────────────────────────────────────────
  MINIMUM_LOT_SIZE    = 16  # col Q  — Minimum Lot Size (texto)
  ZONING              = 17  # col R  — Zoning Code
  JURISDICTION        = 18  # col S  — Jurisdiction
  LAND_USE            = 19  # col T  — Type Lot / Land Use

  # ── PROPIETARIO ──────────────────────────────────────────────────────────────
  OWNER_NAME          = 20  # col U  — Owner Name
  OWNER_MAIL_ADDRESS  = 21  # col V  — Mail Address (NO exponer en API pública)

  # ── DIRECCIÓN ────────────────────────────────────────────────────────────────
  PROPERTY_ADDRESS    = 22  # col W  — Property Address (física)
  ADDRESS             = 22  # (Retrocompatibilidad → misma celda que PROPERTY_ADDRESS)
  ZIP                 = 23  # col X  — Zip Code
  CITY                = 24  # col Y  — Localidad / Ciudad

  # ── LEGAL Y CARACTERÍSTICAS ──────────────────────────────────────────────────
  LEGAL_DESCRIPTION   = 25  # col Z  — Legal Description
  CRIME_LEVEL         = 26  # col AA — Crime level ("Low" | "Moderate" | "High")
  HOMESTEAD_FLAG      = 27  # col AB — Homestead x Investor ("Homestead" | "Investor")

  # ⛔ col AC (28) — Regrid Link (IGNORADA desde 2026-04-24)
  # ⛔ col AD (29) — GIS Map Image (IGNORADA desde 2026-04-24)

  # ── URLs Y SERVICIOS ─────────────────────────────────────────────────────────
  GOOGLE_MAPS_URL     = 30  # col AE — Google Maps URL
  ELECTRIC            = 31  # col AF — Electric ("yes" | "no")
  WATER               = 32  # col AG — Water ("yes" | "no")
  SEWER               = 33  # col AH — Sewer ("yes" | "no")

  # ⛔ col AI (34) — Highest Elevation (uso interno, IGNORADA)
  # ⛔ col AJ (35) — Lowest Elevation (uso interno, IGNORADA)
  # ⛔ col AK (36) — Elevation difference (uso interno, IGNORADA)

  LOT_SHAPE           = 37  # col AL — Forma Terreno ("Flat" etc.)

  # ⛔ col AM (38) — NEIGHBOR address (IGNORADA)

  COORDINATES_RAW     = 39  # col AN — Coordinates Lat x Log

  # ── FEMA Y MEDIOAMBIENTE ─────────────────────────────────────────────────────
  WETLANDS_RAW        = 40  # col AO — Wetlands ("yes" | "no" → boolean)
  FEMA_NOTES          = 41  # col AP — Comments on FEMA image
  FEMA_URL            = 42  # col AQ — Link FEMA
  FEMA_RISK_LEVEL     = 43  # col AR — Risk factor/FEMA Image label
  PROPERTY_IMAGE_URL  = 44  # col AS — Property Image URL

  # ⛔ col AT (45) — Zillow (metadata, IGNORADA)

  HOA                 = 46  # col AU — POA/HOA ("yes" | "no")

  # ⛔ cols AV→BS (47→70) — Zillow Link 1 + Zillow comps ×4 (IGNORADAS)

  # ── ESTIMACIONES E INVERSIÓN ─────────────────────────────────────────────────
  ESTIMATED_SALE_VALUE  = 71  # col BT — Estimate Sale (sites)
  PRICE_ESTIMATE        = 72  # col BU — Price Estimate
  # ⛔ col BV (73) — Valor Ajustado al 16% (IGNORADA)
  MAX_BID_30            = 74  # col BW — Max Bid at 30%
  MAX_BID_35            = 75  # col BX — Max Bid at 35%

  # ── ANÁLISIS Y URLS FINALES ──────────────────────────────────────────────────
  TECHNICAL_ANALYSIS    = 76  # col BY — Technical analysis
  PROPERTY_APPRAISER_URL = 77 # col BZ — Property Apraisal Page
  CLERK_URL             = 78  # col CA — Clerk of Courts Page
  TAX_COLLECTOR_URL     = 79  # col CB — Tax Collector Page

  # ⛔ col CC (80) — Realforeclose Page (IGNORADA)
  # ⛔ col CD (81) — Zoning Ordinances (IGNORADA)

  # ── COLUMNAS IGNORADAS (documentadas para referencia) ────────────────────────
  IGNORED_INTERNAL  = [4, 5, 6, 28, 29, 34, 35, 36, 38, 45, 47, 73, 80, 81].freeze
  IGNORED_ZILLOW    = (48..70).to_a.freeze
end
