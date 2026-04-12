# frozen_string_literal: true

# GoogleMapsHelper — Server-side injection of Google Maps API credentials.
#
# SECURITY: The API key is rendered into an HTML <script> tag via ERB,
# never interpolated directly in client-side JavaScript.
#
# MANDATORY: Configure HTTP Referrer restrictions in GCP Console:
#   - cloud.taxsaleresources.com/*
#   - localhost:3000/* (dev only)
# Also restrict enabled APIs to: Maps JS API, Street View Static API, Geocoding API.
#
# Usage in layouts:  <%= google_maps_script_tag %>
module GoogleMapsHelper
  def google_maps_script_tag
    return unless ENV['GOOGLE_MAPS_API_KEY'].present?

    api_url = "https://maps.googleapis.com/maps/api/js?key=#{ENV['GOOGLE_MAPS_API_KEY']}&libraries=marker&v=weekly"

    html = tag.script(src: api_url, async: true, defer: true)

    # Optional Map ID for Advanced Markers (AdvancedMarkerElement)
    if ENV['GOOGLE_MAPS_MAP_ID'].present?
      html += "\n    ".html_safe + tag.meta(
        name: "google-maps-map-id",
        content: ENV['GOOGLE_MAPS_MAP_ID']
      )
    end

    html
  end
end
