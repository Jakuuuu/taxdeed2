# frozen_string_literal: true

# SheetColumnMap — Mapeo posicional de columnas del Google Sheet (0-based)
#
# REGLA: Las columnas del Sheet están en un orden fijo.
# Usar SIEMPRE estas constantes — nunca índices numéricos directos.
# Verificar contra el Sheet real si hay dudas.
#
# ⚠️ ACTUALIZADO 2026-04-18: Se insertó "Sale Venue" en col C (pos 2).
#    Todas las posiciones desde la antigua pos 2 se corrieron +1.
#
# ⚠️ ACTUALIZADO 2026-04-21: Se insertaron 3 columnas internas de elevación
#    en AI/AJ/AK (pos 34-36). Todas las posiciones desde la antigua pos 34
#    se corrieron +3. Columnas de elevación = IGNORADAS (uso interno).
#    Verificado contra HEADER MAP real del Sheet "Propiedades1".
#
module SheetColumnMap
  # ── IDENTIFICACIÓN Y UBICACIÓN ──────────────────────────────────────────────
  STATE               = 0   # col A  — Estado
  COUNTY              = 1   # col B  — Condado
  SALE_VENUE          = 2   # col C  — Sale Venue (NUEVA — 2026-04-18)
  PARCEL_ID           = 3   # col D  — Parcel Number

  ESTATUS             = 4   # col E  — Estatus
  NOTAS               = 5   # col F  — NOTAS internas
  COMMENTS_DO_VA      = 6   # col G  — Comments do VA (Anlisis del Virtual Assistant)

  AUCTION_DATE        = 7   # col H  — Auction Date (MM/DD/YYYY)
  MARKET_VALUE        = 8   # col I  — Appraisal (Market Value)
  OPENING_BID         = 9   # col J  — Min. Bid
  ASSESSED_VALUE      = 10  # col K  — Assessed Value
  LOT_AREA_ACRES      = 11  # col L  — Lot Area (acres)
  SQFT_LOT            = 12  # col M  — Lot Area sqft
  SQFT_LIVING         = 13  # col N  — Lot Area Home (sqft)

  HAB                 = 14  # col O  — Habitaciones (bathrooms/rooms)
  BD                  = 15  # col P  — Dormitorios (bedrooms)

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
  # ⛔ col AI (34) — High Elevation (NUEVO — interno, 2026-04-21)
  # ⛔ col AJ (35) — Lowest Elevation (NUEVO — interno, 2026-04-21)
  # ⛔ col AK (36) — Elevation Difference (NUEVO — interno, 2026-04-21)

  LOT_SHAPE           = 37  # col AL — Forma Terreno ("Flat" etc.)  [was AI/34, +3]

  # ⛔ col AM (38) — NEIGHBOR address  [was AJ/35]
  COORDINATES_RAW     = 39  # col AN — Coordinates Lat x Log  [was AK/36, +3]

  WETLANDS_RAW        = 40  # col AO — Wetlands ("yes" | "no" → boolean)  [was AL/37, +3]
  FEMA_NOTES          = 41  # col AP — Comments on FEMA image  [was AM/38, +3]
  FEMA_URL            = 42  # col AQ — Link FEMA  [was AN/39, +3]
  FEMA_RISK_LEVEL     = 43  # col AR — Risk factor/FEMA Image label  [was AO/40, +3]
  PROPERTY_IMAGE_URL  = 44  # col AS — Property Image URL  [was AP/41, +3]

  # ⛔ col AT (45) — Zillow (metadata / string)  [was AQ/42]

  HOA                 = 46  # col AU — POA/HOA ("yes" | "no")  [was AR/43, +3]

  # ⛔ cols AV→BS (47→70) — Zillow comps (Links, Price, Sqft, Acres, etc.)  [was AS→BP/44→67]

  ESTIMATED_SALE_VALUE = 71 # col BT — Estimate Sale (sites)  [was BQ/68, +3]

  # ⛔ cols BU→CA (72→78) — Cálculos duplicados y estimaciones extra  [was BR→BX/69→75]

  CLERK_URL           = 79  # col CB — Clerk of Courts URL  [was BY/76, +3]
  TAX_COLLECTOR_URL   = 80  # col CC — Tax Collector URL  [was BZ/77, +3]

  # ⛔ cols CD→CE (81→82) — Realforeclose, Zoning Ordinances  [was CA→CB/78→79]

  # ── COLUMNAS IGNORADAS (documentadas para referencia) ────────────────────────
  IGNORED_INTERNAL  = [4, 5, 34, 35, 36, 38, 45, 81, 82].freeze  # col 6 (COMMENTS_DO_VA) ahora se mapea
  IGNORED_ZILLOW    = (47..70).to_a.freeze
  IGNORED_CALCS     = (72..78).to_a.freeze
end
