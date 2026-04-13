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
# ANTI-DOUBLE-INIT: The helper emits a guard that prevents re-injecting the
# Google Maps <script> if it's already present in the DOM (Turbo Drive compat).
#
# Usage in layouts:  <%= google_maps_script_tag %>
module GoogleMapsHelper
  def google_maps_script_tag
    return unless ENV['GOOGLE_MAPS_API_KEY'].present?

    api_url = "https://maps.googleapis.com/maps/api/js?key=#{ENV['GOOGLE_MAPS_API_KEY']}&libraries=marker&v=weekly&loading=async"

    # Guard script: prevent Turbo from re-injecting the Google Maps API script
    # on subsequent navigations (causes "google.maps already loaded" errors)
    guard_script = tag.script(<<~JS.html_safe)
      (function() {
        if (document.querySelector('script[src*="maps.googleapis.com/maps/api/js"]')) return;
        var s = document.createElement('script');
        s.src = #{api_url.to_json};
        s.async = true;
        s.defer = true;
        document.head.appendChild(s);
      })();
    JS

    html = guard_script

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
