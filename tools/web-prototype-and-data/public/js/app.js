/**
 * Bucharest Public Transport - Main Application Controller
 * Redesigned according to Apple Design Guidelines (WWDC Fluid Interfaces):
 * - Direct manipulation, pointer events & velocity handoff
 * - Fluid response on pointer-down with haptic causality
 * - Squircles, materials, depth, and optical typography
 * - Floating Apple Maps spatial hierarchy
 */

class AppController {
  constructor() {
    this.map = null;
    this.vehicles = [];
    this.routes = [];
    this.stats = null;
    this.activeFilter = {
      mode: 'all',
      line: '',
      crowded: false
    };
    this.selectedLine = null;
    this.activeLineData = null;
    this.lineDirectionMode = 'both'; // 'both' | 'tur' | 'retur'
    this.showLineStations = true;
    this.filterOnRouteOnly = true; // Default: show only vehicles in active revenue service
    this.filterActiveGpsOnly = false;
    this.knownDepots = [
      { name: "Autobaza Nordului", lat: 44.4887, lon: 26.0853 },
      { name: "Autobaza Militari", lat: 44.4327, lon: 26.0038 },
      { name: "Autobaza Bujoreni", lat: 44.4263, lon: 26.0111 },
      { name: "Autobaza Alexandria", lat: 44.4010, lon: 26.0422 },
      { name: "Autobaza Ferentari", lat: 44.3873, lon: 26.0835 },
      { name: "Autobaza Berceni", lat: 44.3901, lon: 26.1211 },
      { name: "Autobaza Obregia", lat: 44.3760, lon: 26.1200 },
      { name: "Autobaza Titan", lat: 44.4038, lon: 26.2047 },
      { name: "Autobaza Floreasca", lat: 44.4603, lon: 26.1036 },
      { name: "Autobaza Giurgiului", lat: 44.3693, lon: 26.0994 },
      { name: "Depoul Vatra Luminoasă", lat: 44.4380, lon: 26.1484 },
      { name: "Depoul Militari", lat: 44.4292, lon: 25.9767 },
      { name: "Depoul Bucureștii Noi", lat: 44.4792, lon: 26.0445 },
      { name: "Depoul Victoria", lat: 44.4528, lon: 26.0901 },
      { name: "Depoul Colentina", lat: 44.4726, lon: 26.1547 },
      { name: "Depoul Dudești", lat: 44.4212, lon: 26.1321 },
      { name: "Depoul Titan", lat: 44.4019, lon: 26.2024 },
      { name: "Depoul Giurgiului", lat: 44.3706, lon: 26.0983 },
      { name: "Depoul Alexandria", lat: 44.3993, lon: 26.0460 }
    ];
    this.selectedVehicle = null;
    this.followingVehicle = false;
    this.cooldownSeconds = 12;
    this.countdownTimer = null;
    this.theme = 'dark';

    // Bilet TB Ticketing State (Reverse-engineered from official app)
    this.biletStatus = { authenticated: false, account: null };
    this.biletActiveTickets = [];
    this.biletAvailablePackages = [];
    this.biletCatalog = [];
    this.ticketCountdownTimer = null;
    this.activeBiletTab = 'active';
  }

  /**
   * Micro-haptic tactile feedback (Apple Causality & Utility principle)
   */
  triggerHaptic(duration = 8) {
    if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
      try {
        navigator.vibrate(duration);
      } catch (e) {}
    }
  }

  /**
   * Initialize App
   */
  async init() {
    console.log("Initializing Apple Design Bucharest Transit App...");

    // Initialize Map
    this.map = new TransitMap('map');
    this.map.init();

    // Map vehicle click handler
    this.map.onVehicleSelect((v) => {
      this.triggerHaptic(12);
      this.showVehicleInspector(v);
    });

    // Setup UI Event Listeners
    this.setupEventListeners();

    // Setup Mobile Tab Bar
    this.setupMobileTabBar();

    // Setup Direct Manipulation for Sheets
    this.initSheetGestures();

    // Setup Bilet TB Listeners & Data
    this.setupBiletTbEventListeners();
    await this.loadBiletTbData();
    this.startTicketCountdown();

    // Load initial routes & stats
    await this.loadInitialData();

    // Start live sync cycle
    this.startSyncCycle();
  }

  /**
   * Setup UI Event Listeners
   */
  setupEventListeners() {
    // Mode Filter Chips
    document.querySelectorAll('.chip-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        this.triggerHaptic(8);
        document.querySelectorAll('.chip-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        
        const mode = btn.dataset.mode;
        if (mode === 'crowded') {
          this.activeFilter.mode = 'all';
          this.activeFilter.crowded = true;
          this.filterActiveGpsOnly = false;
        } else if (mode === 'active_gps') {
          this.activeFilter.mode = 'all';
          this.activeFilter.crowded = false;
          this.filterActiveGpsOnly = true;
        } else {
          this.activeFilter.mode = mode;
          this.activeFilter.crowded = false;
          this.filterActiveGpsOnly = false;
        }
        this.applyFilters();
      });
    });

    // Search Input with Real-time Autocomplete
    const searchInput = document.getElementById('search-input');
    const clearBtn = document.getElementById('clear-search-btn');
    const autoList = document.getElementById('search-autocomplete-list');

    searchInput.addEventListener('input', (e) => {
      const query = e.target.value.trim();
      this.activeFilter.line = query;
      clearBtn.style.display = query ? 'flex' : 'none';

      // Render autocomplete suggestions
      this.renderSearchAutocomplete(query);
      this.applyFilters();
    });

    searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        const query = searchInput.value.trim().toUpperCase();
        if (query) {
          const match = this.routes.find(r => r.line.toUpperCase() === query);
          if (match) {
            this.selectLine(match.line);
            if (autoList) autoList.style.display = 'none';
          } else if (autoList && autoList.firstElementChild) {
            autoList.firstElementChild.click();
          }
        }
      } else if (e.key === 'Escape') {
        if (autoList) autoList.style.display = 'none';
      }
    });

    clearBtn.addEventListener('click', () => {
      this.triggerHaptic(8);
      searchInput.value = '';
      this.activeFilter.line = '';
      clearBtn.style.display = 'none';
      if (autoList) autoList.style.display = 'none';
      if (this.selectedLine) {
        this.closeLineExplorer();
      } else {
        this.applyFilters();
      }
    });

    // Floating Dock Buttons & Modal Sheets
    this.setupModalTrigger('open-tickets-btn', 'tickets-modal', 'close-tickets-modal-btn');
    this.setupModalTrigger('open-lines-btn', 'lines-modal', 'close-lines-modal-btn');
    this.setupModalTrigger('open-layers-btn', 'layers-modal', 'close-layers-modal-btn');
    this.setupModalTrigger('open-stats-btn', 'stats-modal', 'close-stats-modal-btn');
    this.setupModalTrigger('info-modal-btn', 'info-modal', 'close-modal-btn');

    const chipTickets = document.getElementById('chip-tickets-btn');
    if (chipTickets) {
      chipTickets.addEventListener('click', () => {
        this.triggerHaptic(10);
        const modal = document.getElementById('tickets-modal');
        if (modal) modal.classList.add('active');
      });
    }

    const quickTicketPill = document.getElementById('quick-ticket-pill');
    if (quickTicketPill) {
      quickTicketPill.addEventListener('click', () => {
        this.triggerHaptic(10);
        const modal = document.getElementById('tickets-modal');
        if (modal) modal.classList.add('active');
      });
    }

    // Global Dismiss on Scrim Click or Escape Key
    document.querySelectorAll('.apple-modal-scrim').forEach(scrim => {
      scrim.addEventListener('click', (e) => {
        if (e.target === scrim) {
          scrim.classList.remove('active');
          this.updateTabBarSelection('map');
        }
      });
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        document.querySelectorAll('.apple-modal-scrim.active').forEach(s => s.classList.remove('active'));
        this.updateTabBarSelection('map');
        if (autoList) autoList.style.display = 'none';
      }
    });

    // Refresh Button
    document.getElementById('refresh-btn').addEventListener('click', () => {
      this.triggerHaptic(12);
      this.manualRefresh();
    });

    // Geolocation / My Location Button
    document.getElementById('locate-btn').addEventListener('click', () => {
      this.triggerHaptic(12);
      this.locateUser();
    });

    // Theme Toggle
    document.getElementById('theme-toggle-btn').addEventListener('click', () => {
      this.triggerHaptic(10);
      this.toggleTheme();
    });

    // Inspector Close Button
    document.getElementById('close-insp-btn').addEventListener('click', () => {
      this.triggerHaptic(6);
      this.hideVehicleInspector();
    });

    // Inspector Follow Button
    document.getElementById('follow-veh-btn').addEventListener('click', () => {
      this.triggerHaptic(10);
      this.followingVehicle = !this.followingVehicle;
      const btn = document.getElementById('follow-veh-btn');
      btn.textContent = this.followingVehicle ? '📍 Oprește' : '🎯 Urmărește';
      btn.style.background = this.followingVehicle ? 'var(--apple-red)' : 'var(--apple-blue)';
    });

    // Inspector Show Line Route
    document.getElementById('show-route-btn').addEventListener('click', () => {
      this.triggerHaptic(10);
      if (this.selectedVehicle) {
        this.selectLine(this.selectedVehicle.line);
      }
    });

    // Line Explorer Direction Buttons (Ambele / Tur / Retur)
    document.querySelectorAll('.dir-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        this.triggerHaptic(8);
        const dir = btn.dataset.dir;
        this.setLineDirection(dir);
      });
    });

    // Line Explorer Stations Toggle Checkbox
    const stationsCb = document.getElementById('toggle-line-stations-cb');
    if (stationsCb) {
      stationsCb.addEventListener('change', (e) => {
        this.triggerHaptic(6);
        this.showLineStations = e.target.checked;
        this.renderLineOnMap();
      });
    }

    // Line Explorer Close Button
    const closeExplorerBtn = document.getElementById('close-line-explorer-btn');
    if (closeExplorerBtn) {
      closeExplorerBtn.addEventListener('click', () => {
        this.triggerHaptic(6);
        this.closeLineExplorer();
      });
    }

    // Line Explorer On-Route vs All-Assigned Segmented Filter
    const filterOnRouteBtn = document.getElementById('filter-on-route-btn');
    const filterAllAssignedBtn = document.getElementById('filter-all-assigned-btn');
    if (filterOnRouteBtn && filterAllAssignedBtn) {
      filterOnRouteBtn.addEventListener('click', () => {
        this.triggerHaptic(8);
        this.filterOnRouteOnly = true;
        filterOnRouteBtn.classList.add('active');
        filterAllAssignedBtn.classList.remove('active');
        this.fetchVehiclesData();
      });

      filterAllAssignedBtn.addEventListener('click', () => {
        this.triggerHaptic(8);
        this.filterOnRouteOnly = false;
        filterAllAssignedBtn.classList.add('active');
        filterOnRouteBtn.classList.remove('active');
        this.fetchVehiclesData();
      });
    }

    // Layer Checkbox Toggles
    document.querySelectorAll('.layer-checkbox').forEach(cb => {
      cb.addEventListener('change', async (e) => {
        this.triggerHaptic(8);
        const layerKey = e.target.dataset.layer;
        const color = e.target.dataset.color || '#0a84ff';
        const weight = parseInt(e.target.dataset.weight || '4');

        if (e.target.checked) {
          const geojson = await API.getLayer(layerKey);
          this.map.toggleLayer(layerKey, geojson, { color, weight });
        } else {
          this.map.toggleLayer(layerKey, null);
        }
      });
    });
  }

  /**
   * Helper to bind Apple Modal triggers
   */
  setupModalTrigger(openBtnId, modalId, closeBtnId) {
    const openBtn = document.getElementById(openBtnId);
    const modal = document.getElementById(modalId);
    const closeBtn = document.getElementById(closeBtnId);

    const tabNameMap = {
      'tickets-modal': 'tickets',
      'lines-modal': 'lines',
      'stats-modal': 'stats',
      'layers-modal': 'layers'
    };

    if (openBtn && modal) {
      openBtn.addEventListener('click', () => {
        this.triggerHaptic(10);
        // Close other modals first
        document.querySelectorAll('.apple-modal-scrim.active').forEach(s => s.classList.remove('active'));
        modal.classList.add('active');
        if (tabNameMap[modalId]) {
          this.updateTabBarSelection(tabNameMap[modalId]);
        }
      });
    }

    if (closeBtn && modal) {
      closeBtn.addEventListener('click', () => {
        this.triggerHaptic(6);
        modal.classList.remove('active');
        this.updateTabBarSelection('map');
      });
    }
  }

  /**
   * Setup iOS Native Bottom Tab Bar
   */
  setupMobileTabBar() {
    const tabMap = {
      'map': null,
      'lines': 'lines-modal',
      'tickets': 'tickets-modal',
      'stats': 'stats-modal',
      'layers': 'layers-modal'
    };

    document.querySelectorAll('.ios-tab-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        this.triggerHaptic(10);
        const tab = btn.dataset.tab;
        const targetModalId = tabMap[tab];

        // Close all modal dialogs first
        document.querySelectorAll('.apple-modal-scrim.active').forEach(s => s.classList.remove('active'));

        if (targetModalId) {
          const modal = document.getElementById(targetModalId);
          if (modal) {
            modal.classList.add('active');
          }
          this.updateTabBarSelection(tab);
        } else {
          // 'map' tab: user navigated back to map
          this.updateTabBarSelection('map');
        }
      });
    });
  }

  /**
   * Update active tab in the iOS Bottom Tab Bar
   */
  updateTabBarSelection(activeTab = 'map') {
    document.querySelectorAll('.ios-tab-btn').forEach(btn => {
      if (btn.dataset.tab === activeTab) {
        btn.classList.add('active');
        btn.setAttribute('aria-selected', 'true');
      } else {
        btn.classList.remove('active');
        btn.setAttribute('aria-selected', 'false');
      }
    });
  }

  /**
   * Direct Manipulation: 1:1 Gesture Tracking for Sheets
   * Implements grab offset, pointer capture, and momentum projection (§2 & §6)
   */
  initSheetGestures() {
    document.querySelectorAll('.sheet-grabber').forEach(grabber => {
      const sheet = grabber.closest('.apple-sheet') || grabber.closest('.apple-modal-dialog');
      if (!sheet) return;

      let startY = 0;
      let currentY = 0;
      let isDragging = false;
      let history = [];

      grabber.addEventListener('pointerdown', (e) => {
        isDragging = true;
        grabber.setPointerCapture(e.pointerId);
        startY = e.clientY;
        history = [{ y: e.clientY, t: performance.now() }];
        sheet.style.transition = 'none';
      });

      grabber.addEventListener('pointermove', (e) => {
        if (!isDragging) return;
        currentY = e.clientY;
        const deltaY = currentY - startY;

        // Soft rubber-banding if dragging upwards past resting bounds
        let appliedY = deltaY;
        if (deltaY < 0) {
          appliedY = -Math.pow(-deltaY, 0.85);
        }

        sheet.style.transform = `translateY(${appliedY}px)`;
        history.push({ y: e.clientY, t: performance.now() });
        if (history.length > 5) history.shift();
      });

      const endDrag = (e) => {
        if (!isDragging) return;
        isDragging = false;
        try { grabber.releasePointerCapture(e.pointerId); } catch (_) {}

        // Calculate release velocity (px/s)
        let velocity = 0;
        if (history.length >= 2) {
          const first = history[0];
          const last = history[history.length - 1];
          const dt = (last.t - first.t) / 1000;
          if (dt > 0) velocity = (last.y - first.y) / dt;
        }

        // Apple momentum projection formula: (v / 1000) * 0.998 / (1 - 0.998)
        const projectedY = (currentY - startY) + (velocity / 1000) * 0.998 / 0.002;

        sheet.style.transition = 'transform 320ms cubic-bezier(0.16, 1, 0.3, 1)';

        if (projectedY > 120 || velocity > 600) {
          // Flicked down or dragged down -> dismiss sheet
          sheet.style.transform = 'translateY(100%)';
          setTimeout(() => {
            if (sheet.classList.contains('apple-modal-dialog')) {
              const scrim = sheet.closest('.apple-modal-scrim');
              if (scrim) scrim.classList.remove('active');
              this.updateTabBarSelection('map');
            } else if (sheet.id === 'line-explorer-card') {
              this.closeLineExplorer();
            } else if (sheet.id === 'vehicle-inspector-card') {
              this.hideVehicleInspector();
            }
            sheet.style.transform = '';
          }, 320);
        } else {
          // Snap back home
          sheet.style.transform = 'translateY(0)';
        }
      };

      grabber.addEventListener('pointerup', endDrag);
      grabber.addEventListener('pointercancel', endDrag);
    });
  }

  /**
   * Load Initial Data (Routes, Stats, First Vehicles Fetch)
   */
  async loadInitialData() {
    this.routes = await API.getRoutes();
    this.renderRoutesList(this.routes);

    await this.fetchVehiclesData();
    await this.fetchStatsData();
  }

  /**
   * Calculate Haversine distance in km between two GPS coordinates
   */
  haversineDistanceKm(lat1, lon1, lat2, lon2) {
    const R = 6371.0;
    const dLat = (lat2 - lat1) * Math.PI / 180.0;
    const dLon = (lon2 - lon1) * Math.PI / 180.0;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * Math.PI / 180.0) * Math.cos(lat2 * Math.PI / 180.0) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  /**
   * Check if coordinates are inside or near (<600m) a known bus/tram depot
   */
  findNearbyDepot(lat, lon) {
    for (const depot of this.knownDepots) {
      const d = this.haversineDistanceKm(lat, lon, depot.lat, depot.lon);
      if (d <= 0.6) {
        return depot.name;
      }
    }
    return null;
  }

  /**
   * Calculate minimum distance from vehicle position to line route
   */
  calculateDistanceToRouteKm(lat, lon, lineData) {
    if (!lineData) return 0;

    let coords = [];
    if (lineData.tur_geometry && lineData.tur_geometry.coordinates) {
      coords = coords.concat(lineData.tur_geometry.coordinates);
    }
    if (lineData.retur_geometry && lineData.retur_geometry.coordinates) {
      coords = coords.concat(lineData.retur_geometry.coordinates);
    }

    if (coords.length === 0) return 0;

    let minDist = 999999.0;
    for (let i = 0; i < coords.length; i++) {
      const pt = coords[i];
      const d = this.haversineDistanceKm(lat, lon, pt[1], pt[0]);
      if (d < minDist) {
        minDist = d;
      }
    }
    return minDist;
  }

  /**
   * Enrich vehicle with route proximity, depot status, and GPS age
   */
  calculateVehicleRouteDetails(v, lineData) {
    const now = Date.now();
    const gpsTime = v.gps_timestamp ? new Date(v.gps_timestamp).getTime() : now;
    const ageMinutes = Math.max(0, Math.round((now - gpsTime) / 60000));
    v.gps_age_minutes = ageMinutes;
    v.is_stale_gps = ageMinutes > 25;

    if (lineData && v.latitude && v.longitude) {
      const distKm = this.calculateDistanceToRouteKm(v.latitude, v.longitude, lineData);
      v.distance_to_route_km = Math.round(distKm * 10) / 10;

      // On-route threshold: within 850m of line path
      if (distKm <= 0.85) {
        v.is_on_route = true;
        v.is_off_route = false;
        v.depot_name = null;
      } else {
        v.is_on_route = false;
        v.is_off_route = true;
        v.depot_name = this.findNearbyDepot(v.latitude, v.longitude) || 'Garaj / Depou';
      }
    } else {
      v.is_on_route = true;
      v.is_off_route = false;
      v.distance_to_route_km = 0;
    }

    return v;
  }

  /**
   * Fetch vehicles and update map and UI
   */
  async fetchVehiclesData() {
    const data = await API.getVehicles(this.activeFilter);
    if (data && data.vehicles) {
      this.vehicles = data.vehicles;

      const now = Date.now();
      this.vehicles.forEach(v => {
        const gpsTime = v.gps_timestamp ? new Date(v.gps_timestamp).getTime() : now;
        v.gps_age_minutes = Math.max(0, Math.round((now - gpsTime) / 60000));
        v.is_stale_gps = v.gps_age_minutes > 25;
      });

      let displayVehicles = [...this.vehicles];

      // If line explorer is active
      if (this.selectedLine) {
        const lineKey = this.selectedLine.toUpperCase();
        let lineVehicles = displayVehicles.filter(v => String(v.line).toUpperCase() === lineKey);

        lineVehicles.forEach(v => this.calculateVehicleRouteDetails(v, this.activeLineData));

        const onRouteVehicles = lineVehicles.filter(v => v.is_on_route);
        const offRouteVehicles = lineVehicles.filter(v => v.is_off_route);

        // Update badge counts in Line Explorer
        const onRouteCountEl = document.getElementById('count-on-route');
        const allCountEl = document.getElementById('count-all-assigned');
        if (onRouteCountEl) onRouteCountEl.textContent = onRouteVehicles.length;
        if (allCountEl) allCountEl.textContent = lineVehicles.length;

        // Apply on-route filter
        if (this.filterOnRouteOnly) {
          displayVehicles = onRouteVehicles;
        } else {
          displayVehicles = lineVehicles;
        }

        // Apply direction filter
        if (this.lineDirectionMode === 'tur') {
          displayVehicles = displayVehicles.filter(v => v.direction_id === 0);
        } else if (this.lineDirectionMode === 'retur') {
          displayVehicles = displayVehicles.filter(v => v.direction_id === 1);
        }

        this.updateLineExplorerVehicles(onRouteVehicles, lineVehicles);
        this.renderLineVehiclesStrip(displayVehicles);
      } else {
        if (this.filterActiveGpsOnly) {
          displayVehicles = displayVehicles.filter(v => !v.is_stale_gps);
        }
      }

      this.map.updateVehicles(displayVehicles);

      // Update counters
      const statTotalEl = document.getElementById('stat-total-vehicles');
      if (statTotalEl) statTotalEl.textContent = displayVehicles.length;

      const chipAllEl = document.getElementById('chip-count-all');
      if (chipAllEl) chipAllEl.textContent = this.vehicles.length.toLocaleString();

      // If currently following a vehicle, re-center map
      if (this.followingVehicle && this.selectedVehicle) {
        const updatedVeh = this.vehicles.find(v => v.id === this.selectedVehicle.id);
        if (updatedVeh) {
          this.selectedVehicle = updatedVeh;
          this.showVehicleInspector(updatedVeh, false);
          this.map.selectVehicle(updatedVeh.id, true);
        }
      }
    }
  }

  /**
   * Fetch stats and update dashboard
   */
  async fetchStatsData() {
    const stats = await API.getStats();
    if (stats) {
      this.stats = stats;
      this.renderStatsDashboard(stats);
    }
  }

  /**
   * Start 12-second live sync cycle with 1-second countdown ticks
   */
  startSyncCycle() {
    let secondsLeft = 12;
    const countdownEl = document.getElementById('sync-countdown');

    if (this.countdownTimer) clearInterval(this.countdownTimer);

    this.countdownTimer = setInterval(() => {
      secondsLeft--;
      if (countdownEl) countdownEl.textContent = `${secondsLeft}s`;

      if (secondsLeft <= 0) {
        secondsLeft = 12;
        this.fetchVehiclesData();
        this.fetchStatsData();
      }
    }, 1000);
  }

  /**
   * Manual refresh requested by user
   */
  async manualRefresh() {
    const refreshBtn = document.getElementById('refresh-btn');
    refreshBtn.classList.add('spinning');

    await API.triggerRefresh();
    await this.fetchVehiclesData();
    await this.fetchStatsData();

    setTimeout(() => {
      refreshBtn.classList.remove('spinning');
    }, 600);
  }

  /**
   * Apply Active Search & Filters
   */
  applyFilters() {
    this.fetchVehiclesData();
  }

  /**
   * Render Routes Grid in Directory Modal
   */
  renderRoutesList(routes) {
    const container = document.getElementById('routes-list-container');
    if (!container) return;

    if (!routes || routes.length === 0) {
      container.innerHTML = '<div style="color: var(--apple-secondary-label); padding: 1rem;">Nicio linie disponibilă.</div>';
      return;
    }

    container.innerHTML = routes.map(r => `
      <div class="line-badge-card ${this.selectedLine === r.line ? 'active' : ''}" data-line="${r.line}">
        <div class="line-num" style="background-color: ${r.color || '#0a84ff'};">${r.line}</div>
        <div class="line-type-label">${r.typeName || 'Autobuz'}</div>
        <div class="line-veh-count">${r.active_vehicles > 0 ? `${r.active_vehicles} active` : 'Inactiv'}</div>
      </div>
    `).join('');

    // Attach click events to lines
    container.querySelectorAll('.line-badge-card').forEach(card => {
      card.addEventListener('click', () => {
        this.triggerHaptic(10);
        const line = card.dataset.line;
        // Close modal
        const modal = document.getElementById('lines-modal');
        if (modal) modal.classList.remove('active');
        this.selectLine(line);
      });
    });
  }

  /**
   * Render real-time line autocomplete dropdown
   */
  renderSearchAutocomplete(query) {
    const listEl = document.getElementById('search-autocomplete-list');
    if (!listEl) return;

    if (!query || query.length === 0) {
      listEl.style.display = 'none';
      listEl.innerHTML = '';
      return;
    }

    const q = query.toUpperCase();
    const matchingLines = this.routes.filter(r => r.line.toUpperCase().includes(q));

    if (matchingLines.length === 0) {
      listEl.style.display = 'none';
      listEl.innerHTML = '';
      return;
    }

    listEl.innerHTML = matchingLines.slice(0, 8).map(r => {
      const terminals = r.terminals && r.terminals.length > 0 ? r.terminals.join(' ⇄ ') : (r.typeName || 'Linie Tranzit');
      const vehText = r.active_vehicles > 0 ? `${r.active_vehicles} active` : 'Inactivă';

      return `
        <div class="search-autocomplete-item" data-line="${r.line}">
          <div class="search-auto-left">
            <span class="search-auto-badge" style="background-color: ${r.color || '#0a84ff'};">${r.line}</span>
            <div class="search-auto-info">
              <span class="search-auto-title">Linia ${r.line} &bull; ${r.typeName || 'Tranzit'}</span>
              <span class="search-auto-endpoints">${terminals}</span>
            </div>
          </div>
          <span class="search-auto-veh-count">${vehText}</span>
        </div>
      `;
    }).join('');

    listEl.style.display = 'block';

    // Click handler for autocomplete items
    listEl.querySelectorAll('.search-autocomplete-item').forEach(item => {
      item.addEventListener('click', () => {
        this.triggerHaptic(10);
        const line = item.dataset.line;
        listEl.style.display = 'none';
        this.selectLine(line);
      });
    });
  }

  /**
   * Select a Line: Load Tur & Retur geometries, stations, and vehicles
   */
  async selectLine(lineName) {
    if (!lineName) {
      this.closeLineExplorer();
      return;
    }

    if (this.selectedLine === lineName) {
      this.closeLineExplorer();
      return;
    }

    this.selectedLine = lineName;
    this.activeFilter.line = lineName;
    this.filterOnRouteOnly = true;
    document.getElementById('search-input').value = lineName;
    document.getElementById('clear-search-btn').style.display = 'flex';

    const filterOnRouteBtn = document.getElementById('filter-on-route-btn');
    const filterAllAssignedBtn = document.getElementById('filter-all-assigned-btn');
    if (filterOnRouteBtn && filterAllAssignedBtn) {
      filterOnRouteBtn.classList.add('active');
      filterAllAssignedBtn.classList.remove('active');
    }

    const autoList = document.getElementById('search-autocomplete-list');
    if (autoList) autoList.style.display = 'none';

    // Hide vehicle inspector HUD if open
    this.hideVehicleInspector();

    // Show line explorer sheet
    const card = document.getElementById('line-explorer-card');
    card.style.display = 'flex';

    const routeMeta = this.routes.find(r => r.line === lineName) || {};
    const lineColor = routeMeta.color || '#0a84ff';
    const typeName = routeMeta.typeName || 'Transport Public';

    document.getElementById('line-explorer-badge').textContent = lineName;
    document.getElementById('line-explorer-badge').style.backgroundColor = lineColor;
    document.getElementById('line-explorer-title').textContent = `Linia ${lineName} • ${typeName}`;
    document.getElementById('line-explorer-endpoints').textContent = 'Se încarcă traseul complet (Tur și Retur)...';

    // Fetch line details
    const lineDetails = await API.getLineDetails(lineName);
    this.activeLineData = lineDetails;

    if (lineDetails) {
      const turTerm = lineDetails.tur_terminal || 'Capăt Dus';
      const returTerm = lineDetails.retur_terminal || 'Capăt Întors';
      document.getElementById('line-explorer-endpoints').textContent = `Tur: → ${turTerm} | Retur: → ${returTerm}`;

      // Update direction buttons labels
      const turBtn = document.getElementById('dir-btn-tur');
      const returBtn = document.getElementById('dir-btn-retur');
      if (turBtn) turBtn.textContent = `🔵 Tur (→ ${turTerm.slice(0, 18)})`;
      if (returBtn) returBtn.textContent = `🟢 Retur (→ ${returTerm.slice(0, 18)})`;

      this.renderLineOnMap();
      this.updateLineExplorerVehicles();
      this.renderLineStationsStrip(lineDetails);
    } else {
      document.getElementById('line-explorer-endpoints').textContent = 'Traseu schematic activ';
    }

    this.renderRoutesList(this.routes);
    this.applyFilters();
  }

  /**
   * Render interactive station stops strip in Line Explorer
   */
  renderLineStationsStrip(lineDetails) {
    const container = document.getElementById('line-stations-container');
    if (!container) return;

    let stations = [];
    if (this.lineDirectionMode === 'tur') {
      stations = lineDetails.tur_stations || [];
    } else if (this.lineDirectionMode === 'retur') {
      stations = lineDetails.retur_stations || [];
    } else {
      // Ambele: combine tur and retur uniquely
      stations = (lineDetails.tur_stations || []).concat(lineDetails.retur_stations || []);
    }

    if (stations.length === 0) {
      container.innerHTML = '<span style="font-size: 0.75rem; color: var(--apple-secondary-label); padding: 4px;">Nicio stație indexată pentru acest sens.</span>';
      return;
    }

    container.innerHTML = stations.map((st, idx) => `
      <div class="station-pill-item" data-lat="${st.lat}" data-lon="${st.lon}" data-name="${st.name}">
        <span class="station-pill-dot"></span>
        <span>${st.name}</span>
      </div>
    `).join('');

    // Click handler: pan to station smoothly
    container.querySelectorAll('.station-pill-item').forEach(pill => {
      pill.addEventListener('click', () => {
        this.triggerHaptic(10);
        const lat = parseFloat(pill.dataset.lat);
        const lon = parseFloat(pill.dataset.lon);
        const name = pill.dataset.name;

        if (lat && lon && this.map && this.map.map) {
          this.map.map.flyTo([lat, lon], 16, { duration: 0.7 });
          L.popup()
            .setLatLng([lat, lon])
            .setContent(`
              <div style="padding: 10px 14px; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui;">
                <div style="font-weight: 700; font-size: 13px;">📍 ${name}</div>
                <div style="color: var(--apple-blue); font-size: 11px; margin-top: 2px;">Linia ${this.selectedLine}</div>
              </div>
            `)
            .openOn(this.map.map);
        }
      });
    });
  }

  /**
   * Render interactive vehicles strip in Line Explorer
   */
  renderLineVehiclesStrip(vehicles) {
    const container = document.getElementById('line-vehicles-container');
    if (!container) return;

    if (!vehicles || vehicles.length === 0) {
      container.innerHTML = '<span style="font-size: 0.75rem; color: var(--apple-secondary-label); padding: 4px;">Niciun vehicul în serviciu pe traseu.</span>';
      return;
    }

    container.innerHTML = vehicles.map(v => {
      const psg = v.passengers || {};
      const onBoard = psg.on_board !== null ? `${psg.on_board} psg` : 'Fără date';
      const dirText = v.direction_id === 1 ? 'Retur' : 'Tur';

      return `
        <div class="station-pill-item" data-vid="${v.id}">
          <span style="font-weight: 700; color: var(--apple-blue);">${v.license_plate}</span>
          <span style="opacity: 0.65; font-size: 0.72rem;">(${dirText})</span>
          <span style="font-size: 0.72rem; color: var(--apple-green); font-weight: 600;">👥 ${onBoard}</span>
        </div>
      `;
    }).join('');

    // Click handler: select vehicle and open Placecard
    container.querySelectorAll('.station-pill-item').forEach(pill => {
      pill.addEventListener('click', () => {
        this.triggerHaptic(12);
        const vid = parseInt(pill.dataset.vid);
        const veh = this.vehicles.find(v => v.id === vid);
        if (veh) {
          this.map.selectVehicle(vid, true);
          this.showVehicleInspector(veh);
        }
      });
    });
  }

  /**
   * Render active line on map according to direction mode and stations toggle
   */
  renderLineOnMap() {
    if (!this.activeLineData) return;

    const routeMeta = this.routes.find(r => r.line === this.selectedLine) || {};
    const lineColor = routeMeta.color || '#0a84ff';

    this.map.showLineRoute({
      turGeometry: this.activeLineData.tur_geometry,
      returGeometry: this.activeLineData.retur_geometry,
      turTerminal: this.activeLineData.tur_terminal,
      returTerminal: this.activeLineData.retur_terminal,
      turStations: this.activeLineData.tur_stations || [],
      returStations: this.activeLineData.retur_stations || [],
      directionMode: this.lineDirectionMode,
      showStations: this.showLineStations,
      lineName: this.selectedLine,
      lineColor: lineColor
    });
  }

  /**
   * Set Direction Mode ('both' | 'tur' | 'retur')
   */
  setLineDirection(dirMode) {
    this.lineDirectionMode = dirMode;

    document.querySelectorAll('.dir-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.dir === dirMode);
    });

    this.renderLineOnMap();
    if (this.activeLineData) {
      this.renderLineStationsStrip(this.activeLineData);
    }
    this.updateLineExplorerVehicles();
    this.fetchVehiclesData();
  }

  /**
   * Update live vehicles stats on line explorer card
   */
  updateLineExplorerVehicles(onRouteList, totalList) {
    if (!this.selectedLine) return;

    const lineKey = this.selectedLine.toUpperCase();
    const lineVehicles = totalList || this.vehicles.filter(v => String(v.line).toUpperCase() === lineKey);
    const onRoute = onRouteList || lineVehicles.filter(v => v.is_on_route);

    const turOnRoute = onRoute.filter(v => v.direction_id === 0).length;
    const returOnRoute = onRoute.filter(v => v.direction_id === 1).length;
    const offRouteCount = lineVehicles.length - onRoute.length;

    const statEl = document.getElementById('line-explorer-veh-stat');
    if (statEl) {
      let text = '';
      if (this.lineDirectionMode === 'tur') {
        text = `${turOnRoute} pe Tur`;
      } else if (this.lineDirectionMode === 'retur') {
        text = `${returOnRoute} pe Retur`;
      } else {
        text = `${turOnRoute} Tur • ${returOnRoute} Retur`;
      }
      if (offRouteCount > 0) {
        text += ` (+${offRouteCount} în depou)`;
      }
      statEl.textContent = text;
    }
  }

  /**
   * Close Line Explorer and restore map
   */
  closeLineExplorer() {
    this.selectedLine = null;
    this.activeLineData = null;
    this.lineDirectionMode = 'both';
    this.activeFilter.line = '';

    const card = document.getElementById('line-explorer-card');
    if (card) card.style.display = 'none';

    document.getElementById('search-input').value = '';
    document.getElementById('clear-search-btn').style.display = 'none';
    const autoList = document.getElementById('search-autocomplete-list');
    if (autoList) autoList.style.display = 'none';

    // Reset direction buttons
    document.querySelectorAll('.dir-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.dir === 'both');
    });

    this.map.clearRouteLine();
    this.renderRoutesList(this.routes);
    this.applyFilters();
  }

  /**
   * Render Passenger & Fleet Statistics Dashboard
   */
  renderStatsDashboard(stats) {
    const psg = stats.passenger_telemetry || {};
    
    const totalPsgEl = document.getElementById('stat-total-psg');
    if (totalPsgEl) totalPsgEl.textContent = (psg.total_on_board || 0).toLocaleString();

    const monitoredEl = document.getElementById('stat-monitored-veh');
    if (monitoredEl) monitoredEl.textContent = `${psg.monitored_vehicles || 0} / ${stats.total_vehicles || 0}`;

    const avgPsgEl = document.getElementById('stat-avg-occupancy');
    if (avgPsgEl) avgPsgEl.textContent = `${psg.avg_occupancy || 0} psg/veh`;

    const flowEl = document.getElementById('stat-flow-rates');
    if (flowEl) flowEl.textContent = `+${psg.total_in_flow || 0} / -${psg.total_out_flow || 0}`;

    // Top Busiest Lines List
    const topLinesContainer = document.getElementById('top-crowded-lines-container');
    if (topLinesContainer && psg.top_busiest_lines) {
      topLinesContainer.innerHTML = psg.top_busiest_lines.map(item => `
        <div style="display: flex; align-items: center; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid var(--apple-border-subtle); font-size: 0.85rem;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <span style="font-weight: 800; background: var(--apple-surface); padding: 3px 8px; border-radius: 8px;">Linia ${item.line}</span>
            <span style="color: var(--apple-secondary-label); font-size: 0.72rem;">(${item.active_vehicles} vehicule)</span>
          </div>
          <div style="font-weight: 700; color: var(--apple-blue); font-variant-numeric: tabular-nums;">${item.total_passengers.toLocaleString()} pasageri</div>
        </div>
      `).join('');
    }
  }

  /**
   * Display Vehicle Inspector Floating Placecard
   */
  showVehicleInspector(v, shouldOpen = true) {
    this.selectedVehicle = v;
    const card = document.getElementById('vehicle-inspector-card');
    if (!card) return;

    // Header badge & name
    const badge = document.getElementById('insp-line-badge');
    badge.textContent = v.line;
    badge.style.backgroundColor = v.color || '#0a84ff';

    document.getElementById('insp-mode-title').textContent = `${v.mode_name} (${v.license_plate})`;

    // Fields
    let directionText = v.direction || 'Necunoscut';
    if (v.is_off_route) {
      directionText = `🏢 În afara traseului (${v.depot_name || 'Garaj'}) - ${v.distance_to_route_km} km`;
    } else if (v.is_stale_gps) {
      directionText += ` • ⚠️ GPS inactiv (${Math.round(v.gps_age_minutes / 60)}h)`;
    }
    document.getElementById('insp-direction').textContent = directionText;
    document.getElementById('insp-plate').textContent = v.license_plate || 'N/A';
    document.getElementById('insp-start-time').textContent = v.start_time ? new Date(v.start_time).toLocaleTimeString('ro-RO') : 'Nespecificat';
    document.getElementById('insp-source').textContent = v.source_name || 'Central';

    // Occupancy
    const psg = v.passengers || {};
    const onBoard = psg.on_board !== null ? `${psg.on_board} pasageri` : 'Fără date';
    document.getElementById('insp-psg-count').textContent = onBoard;
    document.getElementById('insp-crowd-label').textContent = psg.crowding_label || 'Fără date';

    const flowText = (psg.in !== null && psg.out !== null) ? `+${psg.in} urcați la ultima stație / -${psg.out} coborâți` : 'Fără date senzor flux';
    document.getElementById('insp-flow-text').textContent = flowText;

    // Progress Bar
    const fill = document.getElementById('insp-progress-fill');
    const pct = psg.occupancy_pct !== null ? psg.occupancy_pct : 0;
    fill.style.width = `${pct}%`;

    if (pct > 75) fill.style.backgroundColor = 'var(--apple-red)';
    else if (pct > 40) fill.style.backgroundColor = 'var(--apple-orange)';
    else fill.style.backgroundColor = 'var(--apple-green)';

    if (shouldOpen) card.classList.add('visible');
  }

  /**
   * Hide Vehicle Inspector Placecard
   */
  hideVehicleInspector() {
    this.selectedVehicle = null;
    this.followingVehicle = false;
    const card = document.getElementById('vehicle-inspector-card');
    if (card) card.classList.remove('visible');
  }

  /**
   * Locate User via HTML5 Geolocation
   */
  locateUser() {
    if (!navigator.geolocation) {
      alert("Geolocația nu este suportată de acest navigator.");
      return;
    }

    const btn = document.getElementById('locate-btn');
    btn.classList.add('active');

    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const lat = pos.coords.latitude;
        const lon = pos.coords.longitude;
        const acc = pos.coords.accuracy || 30;
        this.map.setUserLocation(lat, lon, acc);
        btn.classList.remove('active');
      },
      (err) => {
        alert("Eroare la obținerea locației: " + err.message);
        btn.classList.remove('active');
      },
      { enableHighAccuracy: true, timeout: 8000 }
    );
  }

  /**
   * Toggle Dark / Light Theme
   */
  toggleTheme() {
    this.theme = this.theme === 'dark' ? 'light' : 'dark';
    if (this.theme === 'light') {
      document.body.classList.add('theme-light');
      this.map.setTheme('light');
    } else {
      document.body.classList.remove('theme-light');
      this.map.setTheme('dark');
    }
  }

  // ==========================================================================
  // Bilet TB (STB Ticketing) Controller Methods
  // ==========================================================================

  /**
   * Load Bilet TB status, active titles, and wallet data
   */
  async loadBiletTbData() {
    const status = await API.getBiletTbStatus();
    this.biletStatus = status;

    if (status.authenticated) {
      this.biletActiveTickets = await API.getBiletTbActiveTickets();
      this.biletAvailablePackages = await API.getBiletTbAvailablePackages();
      this.biletCatalog = await API.getBiletTbCatalog();
    }
    this.renderBiletTbView();
  }

  /**
   * Format full calendar date and time (DD.MM.YYYY, HH:mm:ss) matching official app
   */
  formatTicketDate(dateStr) {
    if (!dateStr) return '-';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return dateStr;
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const year = d.getFullYear();
    const hours = String(d.getHours()).padStart(2, '0');
    const minutes = String(d.getMinutes()).padStart(2, '0');
    const seconds = String(d.getSeconds()).padStart(2, '0');
    return `${day}.${month}.${year}, ${hours}:${minutes}:${seconds}`;
  }

  /**
   * Format milliseconds into days, hours, minutes, seconds (DurationFormat)
   */
  formatDuration(ms) {
    if (ms <= 0 || isNaN(ms)) return '00:00:00';
    const s = Math.floor((ms / 1000) % 60);
    const m = Math.floor((ms / (1000 * 60)) % 60);
    const h = Math.floor((ms / (1000 * 60 * 60)) % 24);
    const d = Math.floor(ms / (1000 * 60 * 60 * 24));
    const sStr = s < 10 ? `0${s}` : `${s}`;
    const mStr = m < 10 ? `0${m}` : `${m}`;
    const hStr = h < 10 ? `0${h}` : `${h}`;
    if (d === 0) {
      return `${hStr}:${mStr}:${sStr}`;
    }
    const dayLabel = d > 1 ? 'zile' : 'zi';
    return `${d} ${dayLabel} ${hStr}:${mStr}:${sStr}`;
  }

  /**
   * Start 1-second countdown interval for active tickets
   */
  startTicketCountdown() {
    if (this.ticketCountdownTimer) clearInterval(this.ticketCountdownTimer);

    this.ticketCountdownTimer = setInterval(() => {
      if (!this.biletActiveTickets || this.biletActiveTickets.length === 0) {
        const quickPill = document.getElementById('quick-ticket-countdown');
        if (quickPill) quickPill.textContent = 'Bilet TB';
        return;
      }

      const now = Date.now();
      let earliestRemainingMs = 999999999999;

      this.biletActiveTickets.forEach((t, idx) => {
        let remainingMs = 0;
        if (t.validToDate) {
          const endMs = new Date(t.validToDate).getTime();
          remainingMs = isNaN(endMs) ? 0 : Math.max(0, endMs - now);
        } else if (t.remainingSeconds !== undefined) {
          remainingMs = Math.max(0, t.remainingSeconds * 1000);
          t.remainingSeconds = Math.max(0, t.remainingSeconds - 1);
        }

        if (remainingMs < earliestRemainingMs) {
          earliestRemainingMs = remainingMs;
        }

        const timerEl = document.getElementById(`ticket-timer-${idx}`);
        const bannerEl = document.getElementById(`ticket-countdown-banner-${idx}`);

        if (timerEl) {
          timerEl.textContent = this.formatDuration(remainingMs);
        }
        if (bannerEl) {
          if (remainingMs < 600000) {
            bannerEl.classList.add('warning');
          } else {
            bannerEl.classList.remove('warning');
          }
        }
      });

      // Update Quick Pill in top island
      const quickPill = document.getElementById('quick-ticket-countdown');
      if (quickPill && earliestRemainingMs !== 999999999999) {
        quickPill.textContent = this.formatDuration(earliestRemainingMs);
      }
    }, 1000);
  }

  /**
   * Render real, sharp QR Code using QRCode generator or fallback SVG matrix
   */
  renderQrCodeForTicket(containerEl, seriesCode) {
    if (!containerEl) return;
    containerEl.innerHTML = '';

    if (typeof QRCode !== 'undefined') {
      try {
        new QRCode(containerEl, {
          text: seriesCode || 'STB-2026-98124019',
          width: 170,
          height: 170,
          colorDark: '#000000',
          colorLight: '#ffffff',
          correctLevel: QRCode.CorrectLevel.M
        });
        return;
      } catch (e) {
        console.warn("QRCode rendering fallback:", e);
      }
    }

    // High-fidelity fallback SVG QR code
    containerEl.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" style="width: 170px; height: 170px;">
        <rect fill="white" width="100" height="100"/>
        <rect fill="black" x="8" y="8" width="28" height="28"/>
        <rect fill="white" x="12" y="12" width="20" height="20"/>
        <rect fill="black" x="16" y="16" width="12" height="12"/>
        <rect fill="black" x="64" y="8" width="28" height="28"/>
        <rect fill="white" x="68" y="12" width="20" height="20"/>
        <rect fill="black" x="72" y="16" width="12" height="12"/>
        <rect fill="black" x="8" y="64" width="28" height="28"/>
        <rect fill="white" x="12" y="68" width="20" height="20"/>
        <rect fill="black" x="16" y="72" width="12" height="12"/>
        <rect fill="black" x="44" y="14" width="8" height="14"/>
        <rect fill="black" x="44" y="34" width="12" height="8"/>
        <rect fill="black" x="14" y="44" width="16" height="8"/>
        <rect fill="black" x="38" y="44" width="8" height="18"/>
        <rect fill="black" x="52" y="50" width="16" height="8"/>
        <rect fill="black" x="44" y="70" width="12" height="18"/>
        <rect fill="black" x="64" y="44" width="8" height="8"/>
        <rect fill="black" x="78" y="44" width="14" height="8"/>
        <rect fill="black" x="68" y="68" width="20" height="20"/>
      </svg>
    `;
  }

  /**
   * Render Bilet TB modal view according to auth state
   */
  renderBiletTbView() {
    const loginView = document.getElementById('tickets-login-view');
    const dashboardView = document.getElementById('tickets-dashboard-view');
    const quickPill = document.getElementById('quick-ticket-pill');

    const tabTicketBadge = document.getElementById('tab-ticket-badge');

    if (!this.biletStatus || !this.biletStatus.authenticated) {
      if (loginView) loginView.style.setProperty('display', 'block', 'important');
      if (dashboardView) dashboardView.style.setProperty('display', 'none', 'important');
      if (quickPill) quickPill.style.display = 'none';
      if (tabTicketBadge) tabTicketBadge.style.display = 'none';
      return;
    }

    if (loginView) loginView.style.setProperty('display', 'none', 'important');
    if (dashboardView) dashboardView.style.setProperty('display', 'block', 'important');
    if (quickPill) quickPill.style.display = 'flex';

    // Update iOS Tab Bar Badge
    const activeTicketsCount = (this.biletActiveTickets || []).length;
    if (tabTicketBadge) {
      if (activeTicketsCount > 0) {
        tabTicketBadge.textContent = activeTicketsCount;
        tabTicketBadge.style.display = 'inline-block';
      } else {
        tabTicketBadge.style.display = 'none';
      }
    }

    // Update Profile Header
    const acc = this.biletStatus.account || {};
    const nameEl = document.getElementById('bilet-user-name');
    const emailEl = document.getElementById('bilet-user-email');
    const avatarEl = document.getElementById('bilet-user-avatar');

    if (nameEl) nameEl.textContent = `${acc.firstName || 'Călător'} ${acc.lastName || 'STB'}`;
    if (emailEl) emailEl.textContent = acc.email || 'calator.stb@gmail.com';
    if (avatarEl) {
      const f = (acc.firstName || 'C')[0].toUpperCase();
      const l = (acc.lastName || 'S')[0].toUpperCase();
      avatarEl.textContent = `${f}${l}`;
    }

    // Update Counts
    const activeCountEl = document.getElementById('bilet-count-active');
    const walletCountEl = document.getElementById('bilet-count-wallet');
    const walletTotal = (this.biletAvailablePackages || []).reduce((sum, p) => sum + (p.ticketsRemaining || 0), 0);

    if (activeCountEl) activeCountEl.textContent = (this.biletActiveTickets || []).length;
    if (walletCountEl) walletCountEl.textContent = walletTotal;

    this.switchBiletTab(this.activeBiletTab || 'active');
  }

  /**
   * Render Active Tickets List with Countdown & QR Code
   */
  renderBiletTbActiveTickets() {
    const container = document.getElementById('bilet-active-cards-container');
    if (!container) return;

    if (!this.biletActiveTickets || this.biletActiveTickets.length === 0) {
      container.innerHTML = `
        <div style="text-align: center; padding: 36px 16px; color: var(--apple-secondary-label);">
          <div style="font-size: 3rem; margin-bottom: 8px;">🎟️</div>
          <div style="font-weight: 700; font-size: 1rem; color: var(--apple-label);">Niciun titlu de călătorie activ</div>
          <p style="font-size: 0.78rem; margin: 6px 0 16px 0;">Activează un bilet din portofel sau achiziționează unul nou.</p>
          <button id="btn-goto-wallet" class="apple-btn-primary" style="margin: 0 auto; padding: 9px 18px; font-size: 0.82rem;">
            ⚡ Deschide Portofel
          </button>
        </div>
      `;
      const btnGoto = document.getElementById('btn-goto-wallet');
      if (btnGoto) {
        btnGoto.addEventListener('click', () => {
          this.triggerHaptic(8);
          this.switchBiletTab('wallet');
        });
      }
      return;
    }

    const now = Date.now();

    container.innerHTML = this.biletActiveTickets.map((t, idx) => {
      const vFrom = this.formatTicketDate(t.validFromDate);
      const vTo = this.formatTicketDate(t.validToDate);
      const endMs = t.validToDate ? new Date(t.validToDate).getTime() : 0;
      const remainingMs = !isNaN(endMs) && endMs > 0 ? Math.max(0, endMs - now) : ((t.remainingSeconds || 0) * 1000);

      const fareDisplay = t.isElev ? 'GRATUIT (0.00 RON)' : `${(t.fare || 0).toFixed(2)} RON`;
      const badgeHtml = t.isElev
        ? `<span class="apple-live-capsule" style="background: rgba(52, 199, 89, 0.18); border-color: rgba(52, 199, 89, 0.45); color: var(--apple-green); font-weight: 700;">
             🎓 ELEV (100% GRATUIT)
           </span>`
        : `<span class="apple-live-capsule" style="background: rgba(48, 209, 88, 0.15); border-color: rgba(48, 209, 88, 0.35);">
             <span class="apple-live-dot"></span>
             <span>CONTROL</span>
           </span>`;

      // Check if STB gave us a real base64 QR code image
      const hasQrImage = t.qrCode && typeof t.qrCode === 'string' && t.qrCode.length > 50;

      return `
        <div class="ticket-active-card ${t.isElev ? 'ticket-elev-card' : ''}">
          <!-- Card Top Bar -->
          <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 10px;">
            <div>
              <div style="font-size: 0.7rem; font-weight: 700; text-transform: uppercase; color: var(--apple-green); letter-spacing: 0.04em;">
                ✅ ACTIV &bull; VALABIL PENTRU CONTROL
              </div>
              <h4 style="font-size: 1.05rem; font-weight: 700; letter-spacing: -0.015em; margin-top: 2px; color: var(--apple-label);">
                ${t.title}
              </h4>
              <div style="font-size: 0.72rem; color: var(--apple-secondary-label); margin-top: 1px;">
                ${t.groupName || 'Urban București-Ilfov'} &bull; <strong>${fareDisplay}</strong>
              </div>
            </div>
            ${badgeHtml}
          </div>

          <!-- Countdown Banner -->
          <div id="ticket-countdown-banner-${idx}" class="ticket-countdown-banner">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 1.35rem;">⏳</span>
              <div>
                <div style="font-size: 0.7rem; font-weight: 600; text-transform: uppercase; color: var(--apple-secondary-label);">Timp rămas</div>
                <div id="ticket-timer-${idx}" class="ticket-countdown-time">${this.formatDuration(remainingMs)}</div>
              </div>
            </div>
            <div style="font-size: 0.72rem; color: var(--apple-secondary-label); text-align: right; line-height: 1.35;">
              <div>De la: <strong>${vFrom}</strong></div>
              <div>Până la: <strong>${vTo}</strong></div>
            </div>
          </div>

          <!-- Inspection QR Code Frame -->
          <div class="ticket-qr-frame">
            ${hasQrImage ? `
              <div style="background: white; padding: 10px; border-radius: 12px; display: inline-block; box-shadow: 0 2px 8px rgba(0,0,0,0.06);">
                <img src="${t.qrCode.startsWith('data:') ? t.qrCode : 'data:image/JPEG;base64,' + t.qrCode}" class="qr-image" style="width: 190px; height: 190px; object-fit: contain; display: block;" alt="Cod QR Control STB">
              </div>
            ` : `
              <div id="qrcode-canvas-box-${idx}" style="background: white; padding: 10px; border-radius: 12px; display: inline-block;"></div>
            `}
            <div style="font-size: 0.72rem; font-weight: 700; color: #111111; margin-top: 8px; letter-spacing: 0.02em;">
              SCANARE PENTRU CONTROL STB / TPBI
            </div>
          </div>

          <!-- Series Code & Details -->
          <div style="display: flex; align-items: center; justify-content: space-between; padding-top: 6px; border-top: 1px solid var(--apple-border-subtle); font-size: 0.78rem;">
            <div>
              <span style="color: var(--apple-secondary-label);">Cod Serie:</span>
              <strong class="ticket-series-badge">${t.qrCodeCode || 'STB-ELEV-2026-9845102'}</strong>
            </div>
            <span style="color: var(--apple-green); font-weight: 600; font-size: 0.75rem;">
              ⚡ Titlu de călătorie aprobat
            </span>
          </div>

          <!-- Official Note -->
          <div style="background: rgba(255, 204, 0, 0.12); border-left: 3px solid #ffcc00; padding: 6px 10px; border-radius: 0 6px 6px 0; margin-top: 10px; font-size: 0.69rem; color: var(--apple-label); line-height: 1.3;">
            ⚠️ Valabil pentru controlul efectuat de către agenții STB / TPBI pe întreaga rețea de transport public din regiunea București - Ilfov.
          </div>
        </div>
      `;
    }).join('');

    // Fallback QR code generator if STB image wasn't returned
    this.biletActiveTickets.forEach((t, idx) => {
      const box = document.getElementById(`qrcode-canvas-box-${idx}`);
      if (box && (!t.qrCode || t.qrCode.length < 50)) {
        this.renderQrCodeForTicket(box, t.qrCodeCode);
      }
    });
  }

  /**
   * Render Wallet Available Unactivated Packages
   */
  renderBiletTbWallet() {
    const container = document.getElementById('bilet-wallet-container');
    if (!container) return;

    if (!this.biletAvailablePackages || this.biletAvailablePackages.length === 0) {
      container.innerHTML = `
        <div style="text-align: center; padding: 30px 16px; color: var(--apple-secondary-label);">
          <div style="font-size: 2.4rem; margin-bottom: 6px;">⚡</div>
          <div style="font-weight: 700; font-size: 0.95rem; color: var(--apple-label);">Portofelul este gol</div>
          <p style="font-size: 0.78rem; margin: 4px 0 14px 0;">Achiziționează bilete din catalog pentru a le activa oricând.</p>
          <button id="btn-wallet-to-catalog" class="apple-btn-primary" style="margin: 0 auto; padding: 8px 16px; font-size: 0.8rem;">
            🛒 Mergi la Catalog
          </button>
        </div>
      `;
      const btnToCat = document.getElementById('btn-wallet-to-catalog');
      if (btnToCat) {
        btnToCat.addEventListener('click', () => {
          this.triggerHaptic(8);
          this.switchBiletTab('catalog');
        });
      }
      return;
    }

    container.innerHTML = this.biletAvailablePackages.map(pkg => `
      <div class="wallet-item-card">
        <div class="wallet-item-info">
          <div class="wallet-item-title">${pkg.title}</div>
          <div class="wallet-item-sub">Valabilitate: ${pkg.validPeriodMinutes || 90} minute &bull; ${pkg.ticketsRemaining} bilete rămase</div>
        </div>
        <button class="apple-btn-primary btn-activate-pkg" data-pkg-id="${pkg.id}" style="padding: 7px 14px; font-size: 0.78rem; white-space: nowrap;">
          ⚡ Activează
        </button>
      </div>
    `).join('');

    // Attach activation event
    container.querySelectorAll('.btn-activate-pkg').forEach(btn => {
      btn.addEventListener('click', async () => {
        this.triggerHaptic(12);
        btn.textContent = 'Se activează...';
        btn.disabled = true;

        const pkgId = parseInt(btn.dataset.pkgId);
        const res = await API.activateBiletTb(pkgId);

        if (res && res.success) {
          await this.loadBiletTbData();
          this.switchBiletTab('active');
        } else {
          alert("Eroare la activare: " + (res.error || 'Încearcă din nou'));
          btn.textContent = '⚡ Activează';
          btn.disabled = false;
        }
      });
    });
  }

  /**
   * Render Official STB Ticket Catalog
   */
  renderBiletTbCatalog() {
    const container = document.getElementById('bilet-catalog-container');
    if (!container) return;

    if (!this.biletCatalog || this.biletCatalog.length === 0) {
      container.innerHTML = '<div style="color: var(--apple-secondary-label); padding: 1rem;">Se încarcă catalogul STB...</div>';
      return;
    }

    container.innerHTML = this.biletCatalog.map(item => `
      <div class="wallet-item-card">
        <div class="wallet-item-info">
          <div class="wallet-item-title">${item.name}</div>
          <div class="wallet-item-sub">${item.desc}</div>
          <div style="font-weight: 700; color: var(--apple-blue); font-size: 0.8rem; margin-top: 3px;">${item.fare.toFixed(2)} RON</div>
        </div>
        <button class="apple-btn-secondary btn-buy-catalog" data-cat-id="${item.id}" style="padding: 7px 12px; font-size: 0.78rem; white-space: nowrap;">
          🛒 Cumpără
        </button>
      </div>
    `).join('');

    // Attach purchase event
    container.querySelectorAll('.btn-buy-catalog').forEach(btn => {
      btn.addEventListener('click', async () => {
        this.triggerHaptic(12);
        btn.textContent = 'Procesare...';
        btn.disabled = true;

        const catId = parseInt(btn.dataset.catId);
        const res = await API.purchaseBiletTb(catId);

        if (res && res.success) {
          await this.loadBiletTbData();
          this.switchBiletTab('wallet');
        } else {
          btn.textContent = '🛒 Cumpără';
          btn.disabled = false;
        }
      });
    });
  }

  /**
   * Switch between Active / Wallet / Catalog sub-tabs
   */
  switchBiletTab(tabName) {
    this.activeBiletTab = tabName;

    // Toggle button active class
    const btnActive = document.getElementById('bilet-tab-active-btn');
    const btnWallet = document.getElementById('bilet-tab-wallet-btn');
    const btnCatalog = document.getElementById('bilet-tab-catalog-btn');

    if (btnActive) btnActive.classList.toggle('active', tabName === 'active');
    if (btnWallet) btnWallet.classList.toggle('active', tabName === 'wallet');
    if (btnCatalog) btnCatalog.classList.toggle('active', tabName === 'catalog');

    // Toggle panels
    const panelActive = document.getElementById('bilet-panel-active');
    const panelWallet = document.getElementById('bilet-panel-wallet');
    const panelCatalog = document.getElementById('bilet-panel-catalog');

    if (panelActive) panelActive.style.setProperty('display', tabName === 'active' ? 'flex' : 'none', 'important');
    if (panelWallet) panelWallet.style.setProperty('display', tabName === 'wallet' ? 'flex' : 'none', 'important');
    if (panelCatalog) panelCatalog.style.setProperty('display', tabName === 'catalog' ? 'flex' : 'none', 'important');

    if (tabName === 'active') {
      this.renderBiletTbActiveTickets();
    } else if (tabName === 'wallet') {
      this.renderBiletTbWallet();
    } else if (tabName === 'catalog') {
      this.renderBiletTbCatalog();
    }
  }

  /**
   * Disconnect / Logout handler with immediate UI state update
   */
  async handleLogout() {
    this.triggerHaptic(10);
    this.biletStatus = { authenticated: false, account: null };
    this.renderBiletTbView();
    try {
      await API.logoutBiletTb();
    } catch (err) {
      console.warn("Logout upstream error:", err);
    }
  }

  /**
   * Setup Bilet TB UI Event Listeners
   */
  setupBiletTbEventListeners() {
    // Delegated click listener for bulletproof reliability
    document.addEventListener('click', (e) => {
      const logoutTarget = e.target.closest('#bilet-logout-btn');
      if (logoutTarget) {
        e.preventDefault();
        e.stopPropagation();
        this.handleLogout();
        return;
      }

      const tabTarget = e.target.closest('[data-bilet-tab]');
      if (tabTarget) {
        e.preventDefault();
        e.stopPropagation();
        this.triggerHaptic(8);
        const tab = tabTarget.dataset.biletTab;
        if (tab) this.switchBiletTab(tab);
      }
    });

    // Sub-tab buttons direct listeners
    const btnActive = document.getElementById('bilet-tab-active-btn');
    const btnWallet = document.getElementById('bilet-tab-wallet-btn');
    const btnCatalog = document.getElementById('bilet-tab-catalog-btn');

    if (btnActive) btnActive.addEventListener('click', () => { this.triggerHaptic(8); this.switchBiletTab('active'); });
    if (btnWallet) btnWallet.addEventListener('click', () => { this.triggerHaptic(8); this.switchBiletTab('wallet'); });
    if (btnCatalog) btnCatalog.addEventListener('click', () => { this.triggerHaptic(8); this.switchBiletTab('catalog'); });

    // Login Form Submit
    const loginForm = document.getElementById('tickets-login-form');
    if (loginForm) {
      loginForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        this.triggerHaptic(10);

        const usernameInput = document.getElementById('bilet-login-username');
        const passwordInput = document.getElementById('bilet-login-password');
        const errorEl = document.getElementById('bilet-login-error');
        const submitBtn = document.getElementById('bilet-login-submit-btn');

        const u = usernameInput ? usernameInput.value.trim() : '';
        const p = passwordInput ? passwordInput.value : '';

        if (!u || !p) return;

        submitBtn.disabled = true;
        submitBtn.textContent = 'Autentificare în curs...';
        if (errorEl) errorEl.style.display = 'none';

        const res = await API.loginBiletTb(u, p);
        submitBtn.disabled = false;
        submitBtn.textContent = 'Autentificare Bilet TB';

        if (res && res.success) {
          await this.loadBiletTbData();
        } else {
          if (errorEl) {
            errorEl.textContent = res.error || 'Date de autentificare incorecte.';
            errorEl.style.display = 'block';
          }
        }
      });
    }

    // Demo Login Button (1-Click instant test with Elev pass)
    const demoBtn = document.getElementById('bilet-login-demo-btn');
    if (demoBtn) {
      demoBtn.addEventListener('click', async () => {
        this.triggerHaptic(10);
        const usernameInput = document.getElementById('bilet-login-username');
        const passwordInput = document.getElementById('bilet-login-password');
        if (usernameInput) usernameInput.value = 'elev.stb@gmail.com';
        if (passwordInput) passwordInput.value = 'parola123';

        demoBtn.textContent = 'Autentificare demo...';
        demoBtn.disabled = true;

        await API.loginBiletTb('elev.stb@gmail.com', 'parola123', true);
        await this.loadBiletTbData();

        demoBtn.textContent = '⚡ Autentificare Rapidă Demo (Abonament Elev STB)';
        demoBtn.disabled = false;
      });
    }

    // Password Toggle
    const togglePwdBtn = document.getElementById('bilet-toggle-pwd-btn');
    if (togglePwdBtn) {
      togglePwdBtn.addEventListener('click', () => {
        const pwdInput = document.getElementById('bilet-login-password');
        if (pwdInput) {
          const isPwd = pwdInput.type === 'password';
          pwdInput.type = isPwd ? 'text' : 'password';
          togglePwdBtn.textContent = isPwd ? '🔒' : '👁️';
        }
      });
    }

    // Logout Button direct listener
    const logoutBtn = document.getElementById('bilet-logout-btn');
    if (logoutBtn) {
      logoutBtn.addEventListener('click', (e) => {
        e.preventDefault();
        this.handleLogout();
      });
    }
  }
}

// Instantiate on DOMContentLoaded
window.addEventListener('DOMContentLoaded', () => {
  window.App = new AppController();
  window.App.init();
});
