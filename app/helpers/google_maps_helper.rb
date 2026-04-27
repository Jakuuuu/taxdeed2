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
# TURBO DRIVE COMPAT: The helper emits a loader that:
#   1. Checks if the Google Maps API is ALREADY fully loaded (window.google.maps)
#   2. Checks if a <script> tag is already in-flight (prevents double-injection)
#   3. If neither, dynamically injects the script
#   4. Dispatches a custom 'google-maps:ready' event when the API is available
#
# ADVANCED MARKERS: Only requests the 'marker' library if GOOGLE_MAPS_MAP_ID
# is set. Without a Map ID, Advanced Markers throw errors and trigger the
# "This page can't load Google Maps correctly" modal. When no Map ID is
# configured, the app uses Legacy Markers which work without it.
#
# Usage in layouts:  <%= google_maps_script_tag %>
module GoogleMapsHelper
  # Builds the Street View embed iframe URL with the API key injected
  # server-side. The key is exposed in the iframe src attribute, but is
  # restricted by HTTP Referrer rules in the GCP Console (only requests
  # from approved domains succeed).
  def street_view_iframe_src(parcel)
    return nil unless parcel.respond_to?(:has_coords?) && parcel.has_coords?
    api_key = ENV['GOOGLE_MAPS_API_KEY']
    return nil if api_key.blank?
    parcel.street_view_url(api_key)
  end

  def google_maps_script_tag
    return unless ENV['GOOGLE_MAPS_API_KEY'].present?

    # Only load the 'marker' library if a Map ID is configured
    # (Advanced Markers REQUIRE a Map ID or they throw errors)
    has_map_id = ENV['GOOGLE_MAPS_MAP_ID'].present?
    libraries = has_map_id ? '&libraries=marker' : ''
    api_url = "https://maps.googleapis.com/maps/api/js?key=#{ENV['GOOGLE_MAPS_API_KEY']}#{libraries}&v=weekly&loading=async"

    # Robust loader: handles Turbo Drive layout transitions, login redirects,
    # cached pages, and async script timing. Dispatches 'google-maps:ready'
    # so consumers don't need to poll.
    loader_script = tag.script(<<~JS.html_safe)
      (function() {
        // Already fully loaded — just dispatch ready event
        if (window.google && window.google.maps) {
          document.dispatchEvent(new Event('google-maps:ready'));
          return;
        }

        // Script tag already exists (in-flight from a previous navigation)
        var existing = document.querySelector('script[src*="maps.googleapis.com/maps/api/js"]');
        if (existing) {
          // Wait for it to finish loading, then dispatch
          var waitAttempts = 0;
          var waitPoll = setInterval(function() {
            waitAttempts++;
            if (window.google && window.google.maps) {
              clearInterval(waitPoll);
              document.dispatchEvent(new Event('google-maps:ready'));
            } else if (waitAttempts >= 100) {
              clearInterval(waitPoll);
              console.error('[GoogleMaps] Timed out waiting for existing script to load.');
            }
          }, 100);
          return;
        }

        // Inject the script for the first time
        var s = document.createElement('script');
        s.src = #{api_url.to_json};
        s.async = true;
        s.defer = true;
        s.addEventListener('load', function() {
          // Small delay to let google.maps namespace fully initialize
          var initAttempts = 0;
          var initPoll = setInterval(function() {
            initAttempts++;
            if (window.google && window.google.maps) {
              clearInterval(initPoll);
              document.dispatchEvent(new Event('google-maps:ready'));
            } else if (initAttempts >= 50) {
              clearInterval(initPoll);
              console.error('[GoogleMaps] Script loaded but google.maps not available.');
            }
          }, 50);
        });
        s.addEventListener('error', function() {
          console.error('[GoogleMaps] Failed to load Google Maps script.');
        });
        document.head.appendChild(s);
      })();
    JS

    html = loader_script

    # Optional Map ID for Advanced Markers (AdvancedMarkerElement)
    if has_map_id
      html += "\n    ".html_safe + tag.meta(
        name: "google-maps-map-id",
        content: ENV['GOOGLE_MAPS_MAP_ID']
      )
    end

    html
  end
end
