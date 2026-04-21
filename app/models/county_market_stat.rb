# frozen_string_literal: true

# CountyMarketStat — Ficha macro de un condado para el estudio de mercado (Rama 4).
#
# Clave compuesta: (state, county)
# Fuente: Pestaña "Condados" del Google Sheet (35 columnas)
#
class CountyMarketStat < ApplicationRecord
  # ── Asociaciones ─────────────────────────────────────────────
  has_many :real_estate_monthly_volumes, dependent: :destroy

  # ── Validaciones ─────────────────────────────────────────────
  validates :state,  presence: true
  validates :county, presence: true
  validates :state,  uniqueness: { scope: :county, case_sensitive: false }

  # ── Scopes ───────────────────────────────────────────────────
  scope :active_market,   -> { where(market_status: "Activo") }
  scope :by_state,        ->(s) { where("UPPER(state) = ?", s.to_s.upcase) }
  scope :alphabetical,    -> { order(:state, :county) }
  scope :with_volumes,    -> { includes(:real_estate_monthly_volumes) }

  # Condados que tienen subastas registradas en el sistema
  scope :with_active_auctions, -> {
    where("EXISTS (SELECT 1 FROM auctions WHERE UPPER(auctions.state) = UPPER(county_market_stats.state) " \
          "AND UPPER(auctions.county) = UPPER(county_market_stats.county))")
  }

  # Búsqueda de texto libre
  scope :search_text, ->(q) {
    term = "%#{q}%"
    where("county LIKE ? OR state LIKE ? OR about LIKE ?", term, term, term)
  }

  # ── Display helpers ──────────────────────────────────────────

  def display_name
    "#{county}, #{state}"
  end

  def cities_list
    [city_1, city_2, city_3].compact_blank
  end

  def format_currency(value)
    return "—" if value.blank?
    "$#{number_with_delimiter(value.round(0))}"
  end

  def format_large_currency(value)
    return "—" if value.blank?
    if value >= 1_000_000_000
      "$#{(value / 1_000_000_000.0).round(1)}B"
    elsif value >= 1_000_000
      "$#{(value / 1_000_000.0).round(1)}M"
    else
      format_currency(value)
    end
  end

  def format_percentage(value)
    return "—" if value.blank?
    "#{value}%"
  end

  def format_population
    return "—" if population.blank?
    number_with_delimiter(population)
  end

  # Directorio de contactos para la vista
  def institutional_contacts
    contacts = []
    contacts << { dept: "Planning & Zoning",    contact: planning_zoning_contact }   if planning_zoning_contact.present?
    contacts << { dept: "Building Division",    contact: building_division_contact }  if building_division_contact.present?
    contacts << { dept: "Clerk Office",         contact: clerk_office_contact }       if clerk_office_contact.present?
    contacts << { dept: "Tax Collector",        contact: tax_collector_contact }      if tax_collector_contact.present?
    contacts
  end

  # Links externos para la vista (solo los que tienen valor real, no "Link")
  def external_links
    links = []
    links << { label: "Google Maps",  url: google_maps_url }  if real_url?(google_maps_url)
    links << { label: "Redfin",       url: redfin_url }       if real_url?(redfin_url)
    links << { label: "Census",       url: census_url }       if real_url?(census_url)
    links << { label: "FRED",         url: fred_url }         if real_url?(fred_url)
    links << { label: "Realtor",      url: realtor_url }      if real_url?(realtor_url)
    links << { label: "Budgets",      url: budgets_url }      if real_url?(budgets_url)
    links << { label: "BEA",          url: bea_url }          if real_url?(bea_url)
    links << { label: "FAQ",          url: faq_url }          if real_url?(faq_url)
    links
  end

  private

  def real_url?(val)
    val.present? && val != "Link"
  end

  def number_with_delimiter(number)
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end
end
