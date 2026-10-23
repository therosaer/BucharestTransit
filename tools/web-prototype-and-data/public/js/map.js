/**
 * Bucharest Public Transport - Leaflet Map Manager Module
 * Renders high-performance interactive markers, vector lines, and overlays.
 */

class TransitMap {
  constructor(containerId) {
    this.containerId = containerId;
    this.map = null;
    this.markers = new Map(); // vehicleId -> L.Marker
    this.routeLineLayer = null;
    this.turRouteLayer = null;
    this.returRouteLayer = null;
    this.stationsLayer = null;
    this.overlayLayers = new Map(); // layerKey -> L.GeoJSON
    this.selectedVehicleId = null;
    this.userLocationMarker = null;
    this.userAccuracyCircle = null;
    this.activeBaseLayer = null;
    this.baseLayers = {};
    this.onVehicleSelectCallback = null;
    
    // Default Bucharest center
    this.defaultCenter = [44.4361, 26.1027]; // Piața Universității
    this.defaultZoom = 13;
  }

  /**
   * Initialize map instance and base tiles
   */
  init() {
    this.map = L.map(this.containerId, {
      center: this.defaultCenter,
      zoom: this.defaultZoom,
      minZoom: 10,
      maxZoom: 19,
      zoomControl: false
    });

    // Zoom control at bottom-right
    L.control.zoom({ position: 'bottomright' }).addTo(this.map);

    // Tile provider: Official OpenStreetMap (100% Free, No API Key Required)
    this.osmLayer = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors'
    });
    this.osmLayer.addTo(this.map);

    // Map click closes selection
    this.map.on('click', () => {
      // Blank map click
    });

    console.log("Transit Map initialized with OpenStreetMap at Bucharest coords");
  }

  /**
   * Switch map tile theme
   */
  setTheme(themeName) {
    // Theme switching is handled via CSS on .leaflet-tile-pane
    // keeping OpenStreetMap 100% API-key free in both dark and light modes
    if (this.map) {
      this.map.invalidateSize();
    }
  }

  /**
   * Set callback for vehicle click
   */
  onVehicleSelect(cb) {
    this.onVehicleSelectCallback = cb;
  }

  /**
   * Create custom DivIcon for a vehicle
   */
  createVehicleIcon(v, isSelected = false) {
    const mode = v.mode || 'bus';
    const line = v.line || '?';
    const color = v.color || '#0a84ff';
    const psg = v.passengers || {};
    const crowding = psg.crowding || 'unknown';

    // Occupancy halo
    let haloClass = '';
    if (crowding === 'crowded' || crowding === 'high') haloClass = 'halo-crowded';
    else if (crowding === 'moderate') haloClass = 'halo-moderate';

    const selectedClass = isSelected ? 'selected' : '';
    const offRouteClass = v.is_off_route ? 'off-route' : '';
    const staleGpsClass = v.is_stale_gps ? 'stale-gps' : '';
    const garageBadge = v.is_off_route ? '<span style="position: absolute; top: -5px; right: -5px; font-size: 10px; background: #ff9f0a; border-radius: 50%; width: 16px; height: 16px; display: flex; align-items: center; justify-content: center; box-shadow: 0 1px 4px rgba(0,0,0,0.4);" title="În depou / garaj">🏢</span>' : '';

    const html = `
      <div class="apple-vehicle-marker ${mode} ${haloClass} ${selectedClass} ${offRouteClass} ${staleGpsClass}" style="background-color: ${color}; width: 34px; height: 34px; position: relative;">
        <span>${line}</span>
        ${garageBadge}
      </div>
    `;

    return L.divIcon({
      className: 'custom-vehicle-div-icon',
      html: html,
      iconSize: [34, 34],
      iconAnchor: [17, 17],
      popupAnchor: [0, -18]
    });
  }

  /**
   * Render or update all vehicle markers efficiently
   */
  updateVehicles(vehicles) {
    const currentIds = new Set();

    vehicles.forEach(v => {
      const vid = v.id || `${v.latitude}_${v.longitude}`;
      currentIds.add(vid);

      const lat = v.latitude;
      const lon = v.longitude;
      if (!lat || !lon) return;

      const isSelected = (vid === this.selectedVehicleId);
      const icon = this.createVehicleIcon(v, isSelected);

      if (this.markers.has(vid)) {
        // Update position & icon
        const marker = this.markers.get(vid);
        marker.setLatLng([lat, lon]);
        marker.setIcon(icon);
        marker.vehicleData = v;
      } else {
        // Create new marker
        const marker = L.marker([lat, lon], { icon: icon });
        marker.vehicleData = v;

        // Popup
        marker.bindPopup(() => this.generatePopupContent(marker.vehicleData));

        marker.on('click', () => {
          this.selectVehicle(v.id, false);
          if (this.onVehicleSelectCallback) {
            this.onVehicleSelectCallback(v);
          }
        });

        marker.addTo(this.map);
        this.markers.set(vid, marker);
      }
    });

    // Remove obsolete markers
    for (const [vid, marker] of this.markers.entries()) {
      if (!currentIds.has(vid)) {
        this.map.removeLayer(marker);
        this.markers.delete(vid);
      }
    }
  }

  /**
   * Generate clean popup HTML for a vehicle
   */
  generatePopupContent(v) {
    const psg = v.passengers || {};
    const onBoard = psg.on_board !== null ? `${psg.on_board} pasageri` : 'Date indisponibile';
    const flow = (psg.in !== null && psg.out !== null) ? `+${psg.in} urcați / -${psg.out} coborâți` : 'Fără flux recent';
    const direction = v.direction || 'Necunoscut';
    const plate = v.license_plate || 'N/A';
    const modeName = v.mode_name || 'Autobuz';

    return `
      <div style="padding: 12px 14px; min-width: 220px; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif;">
        <div style="display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid rgba(120, 120, 128, 0.2); padding-bottom: 8px; margin-bottom: 8px;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <span style="background: ${v.color}; color: #fff; font-weight: 800; font-size: 13px; padding: 3px 8px; border-radius: 8px; letter-spacing: -0.02em;">${v.line}</span>
            <strong style="font-size: 13px; letter-spacing: -0.01em;">${modeName}</strong>
          </div>
          <span style="font-size: 11px; opacity: 0.75; font-weight: 600; font-variant-numeric: tabular-nums;">${plate}</span>
        </div>
        <div style="font-size: 12px; line-height: 1.5;">
          <div><span style="opacity: 0.65;">Direcție:</span> <strong>${direction}</strong></div>
          <div><span style="opacity: 0.65;">Pasageri la bord:</span> <strong style="color: var(--apple-blue);">${onBoard}</strong></div>
          <div style="font-size: 11px; opacity: 0.75; margin-top: 2px;">${flow}</div>
          ${v.is_off_route ? `<div style="background: rgba(255, 159, 10, 0.15); border: 1px solid rgba(255, 159, 10, 0.4); color: var(--apple-orange); border-radius: 8px; padding: 3px 8px; font-size: 11px; margin-top: 6px; font-weight: 600;">🏢 În afara traseului (${v.depot_name || 'Autobază / Depou'}) - la ${v.distance_to_route_km || '?'} km</div>` : (v.is_on_route ? `<div style="color: var(--apple-green); font-size: 11px; margin-top: 4px; font-weight: 600;">✅ În circulație pe traseu</div>` : '')}
          ${v.is_stale_gps ? `<div style="color: var(--apple-red); font-size: 10px; margin-top: 3px; font-weight: 600;">⚠️ GPS inactiv de ${Math.round(v.gps_age_minutes / 60)}h</div>` : ''}
          <div style="margin-top: 6px; font-size: 10px; opacity: 0.5;">Sursă: ${v.source_name}</div>
        </div>
      </div>
    `;
  }

  /**
   * Select and highlight a specific vehicle
   */
  selectVehicle(vehicleId, panTo = true) {
    this.selectedVehicleId = vehicleId;

    for (const [vid, marker] of this.markers.entries()) {
      const isSel = (vid === vehicleId);
      marker.setIcon(this.createVehicleIcon(marker.vehicleData, isSel));
      if (isSel && panTo) {
        this.map.flyTo(marker.getLatLng(), Math.max(this.map.getZoom(), 15), {
          duration: 0.8
        });
        marker.openPopup();
      }
    }
  }

  /**
   * Render complete Line Route with Tur, Retur, and Stations support
   * @param {Object} options
   */
  showLineRoute(options = {}) {
    this.clearRouteLine();

    const {
      turGeometry,
      returGeometry,
      turTerminal = 'Capăt Tur',
      returTerminal = 'Capăt Retur',
      turStations = [],
      returStations = [],
      directionMode = 'both', // 'both' | 'tur' | 'retur'
      showStations = true,
      lineName = '',
      lineColor = '#2563eb'
    } = options;

    const layersToFit = [];
    const turColor = lineColor || '#2563eb';
    const returColor = '#10b981'; // distinct emerald for retur

    // 1. Render Tur Geometry (Direction 0)
    if ((directionMode === 'both' || directionMode === 'tur') && turGeometry) {
      this.turRouteLayer = L.geoJSON(turGeometry, {
        style: {
          color: turColor,
          weight: 6,
          opacity: 0.9,
          lineJoin: 'round',
          lineCap: 'round'
        }
      }).addTo(this.map);

      this.turRouteLayer.bindPopup(`
        <div style="font-family: sans-serif; font-size: 12px; padding: 4px;">
          <strong style="color: ${turColor}; font-size: 13px;">Linia ${lineName} &bull; TUR (Dus)</strong><br>
          <span>Spre capăt: <strong>${turTerminal}</strong></span>
        </div>
      `);
      layersToFit.push(this.turRouteLayer);
    }

    // 2. Render Retur Geometry (Direction 1)
    if ((directionMode === 'both' || directionMode === 'retur') && returGeometry) {
      this.returRouteLayer = L.geoJSON(returGeometry, {
        style: {
          color: returColor,
          weight: 5,
          opacity: 0.9,
          dashArray: directionMode === 'both' ? '8, 6' : null,
          lineJoin: 'round',
          lineCap: 'round'
        }
      }).addTo(this.map);

      this.returRouteLayer.bindPopup(`
        <div style="font-family: sans-serif; font-size: 12px; padding: 4px;">
          <strong style="color: ${returColor}; font-size: 13px;">Linia ${lineName} &bull; RETUR (Întors)</strong><br>
          <span>Spre capăt: <strong>${returTerminal}</strong></span>
        </div>
      `);
      layersToFit.push(this.returRouteLayer);
    }

    // 3. Render Stations along route
    if (showStations) {
      this.stationsLayer = L.layerGroup().addTo(this.map);

      const renderStopList = (stations, isTur) => {
        const color = isTur ? turColor : returColor;
        const dirLabel = isTur ? `Tur (&rarr; ${turTerminal})` : `Retur (&rarr; ${returTerminal})`;

        stations.forEach((st, idx) => {
          if (!st.lat || !st.lon) return;
          const marker = L.circleMarker([st.lat, st.lon], {
            radius: 5,
            fillColor: color,
            color: '#ffffff',
            weight: 2,
            opacity: 1,
            fillOpacity: 0.95
          });

          marker.bindPopup(`
            <div style="font-family: sans-serif; font-size: 12px; padding: 4px; min-width: 160px;">
              <div style="font-weight: 800; font-size: 13px; margin-bottom: 2px;">📍 ${st.name}</div>
              <div style="color: ${color}; font-weight: 700;">Linia ${lineName} &bull; ${dirLabel}</div>
              <div style="font-size: 11px; opacity: 0.7; margin-top: 2px;">Stația #${idx + 1} de pe sens</div>
            </div>
          `);

          marker.addTo(this.stationsLayer);
        });
      };

      if (directionMode === 'both' || directionMode === 'tur') {
        renderStopList(turStations, true);
      }
      if (directionMode === 'both' || directionMode === 'retur') {
        renderStopList(returStations, false);
      }
    }

    // 4. Auto-fit bounds
    if (layersToFit.length > 0) {
      try {
        const group = L.featureGroup(layersToFit);
        this.map.fitBounds(group.getBounds(), { padding: [60, 60], maxZoom: 15 });
      } catch (e) {
        console.warn("Could not fit route bounds:", e);
      }
    }
  }

  /**
   * Backward-compatible highlightRouteLine
   */
  async highlightRouteLine(geojsonFeature, color = '#f59e0b') {
    this.clearRouteLine();
    if (!geojsonFeature) return;

    this.routeLineLayer = L.geoJSON(geojsonFeature, {
      style: {
        color: color,
        weight: 5,
        opacity: 0.85,
        dashArray: '8, 6'
      }
    }).addTo(this.map);

    try {
      this.map.fitBounds(this.routeLineLayer.getBounds(), { padding: [50, 50] });
    } catch (e) {}
  }

  /**
   * Clear all highlighted line routes and station markers
   */
  clearRouteLine() {
    if (this.turRouteLayer) {
      this.map.removeLayer(this.turRouteLayer);
      this.turRouteLayer = null;
    }
    if (this.returRouteLayer) {
      this.map.removeLayer(this.returRouteLayer);
      this.returRouteLayer = null;
    }
    if (this.stationsLayer) {
      this.map.removeLayer(this.stationsLayer);
      this.stationsLayer = null;
    }
    if (this.routeLineLayer) {
      this.map.removeLayer(this.routeLineLayer);
      this.routeLineLayer = null;
    }
  }

  /**
   * Toggle a GeoJSON overlay layer (e.g. tram tracks, metro stations)
   */
  toggleLayer(layerKey, geojsonData, styleOptions = {}) {
    if (this.overlayLayers.has(layerKey)) {
      // Remove
      this.map.removeLayer(this.overlayLayers.get(layerKey));
      this.overlayLayers.delete(layerKey);
      return false;
    } else {
      // Add
      if (!geojsonData) return false;

      const layer = L.geoJSON(geojsonData, {
        style: (feature) => {
          return {
            color: styleOptions.color || '#06b6d4',
            weight: styleOptions.weight || 3,
            opacity: styleOptions.opacity || 0.75
          };
        },
        pointToLayer: (feature, latlng) => {
          const props = feature.properties || {};
          const title = props.Denumire || props.Statie || props.name || 'Punct Tranzit';
          
          return L.circleMarker(latlng, {
            radius: styleOptions.radius || 5,
            fillColor: styleOptions.fillColor || styleOptions.color || '#eab308',
            color: '#fff',
            weight: 1.5,
            opacity: 1,
            fillOpacity: 0.85
          }).bindPopup(`<strong>${title}</strong>`);
        }
      }).addTo(this.map);

      this.overlayLayers.set(layerKey, layer);
      return true;
    }
  }

  /**
   * Set user GPS location marker & accuracy circle
   */
  setUserLocation(lat, lon, accuracy = 50) {
    if (this.userLocationMarker) {
      this.userLocationMarker.setLatLng([lat, lon]);
      this.userAccuracyCircle.setLatLng([lat, lon]);
      this.userAccuracyCircle.setRadius(accuracy);
    } else {
      const userIcon = L.divIcon({
        className: 'user-gps-marker',
        html: `
          <div style="background: #3b82f6; width: 18px; height: 18px; border-radius: 50%; border: 3px solid #fff; box-shadow: 0 0 10px rgba(59, 130, 246, 0.8);"></div>
        `,
        iconSize: [18, 18],
        iconAnchor: [9, 9]
      });

      this.userLocationMarker = L.marker([lat, lon], { icon: userIcon }).addTo(this.map);
      this.userLocationMarker.bindPopup('<strong>Locația ta actuală</strong>');

      this.userAccuracyCircle = L.circle([lat, lon], {
        radius: accuracy,
        color: '#3b82f6',
        fillColor: '#3b82f6',
        fillOpacity: 0.15,
        weight: 1
      }).addTo(this.map);
    }

    this.map.flyTo([lat, lon], 15, { duration: 1 });
  }
}

window.TransitMap = TransitMap;
