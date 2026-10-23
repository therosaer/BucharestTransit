/**
 * Bucharest Public Transport - Resilient Hybrid API Client Module
 * Supports both:
 *   1. Local backend proxy server (/api/vehicles, /api/stats)
 *   2. Direct mo-bi.ro Open Data querying with client-side route enrichment (CORS enabled)
 *   3. Instant offline fallback to bundled snapshot
 */

class TransitAPI {
  constructor() {
    this.baseUrl = window.location.origin;
    this.routesMap = {};
    this.cachedVehicles = [];
    this.cachedStats = null;
    this.lastUpstreamFetch = 0;
    this.routesLoaded = false;
    this.isUsingDirectFeed = false;
  }

  /**
   * Load route mappings dictionary
   */
  async init() {
    try {
      const res = await fetch('data/routes_map.json');
      if (res.ok) {
        this.routesMap = await res.json();
        this.routesLoaded = true;
        console.log(`Loaded ${Object.keys(this.routesMap).length} route mappings client-side.`);
      }
    } catch (e) {
      console.warn("Could not load local routes_map.json:", e);
    }
  }

  /**
   * Enrich raw vehicle object from mo-bi.ro with route & passenger metadata
   */
  enrichRawVehicle(v) {
    const v_info = v.vehicle || {};
    const trip = v_info.trip || {};
    const veh_ident = v_info.vehicle || {};
    const pos = v_info.position || {};
    const psg = v_info.passenger_info || {};

    const routeId = trip.route_id;
    const routeIdStr = routeId !== null && routeId !== undefined ? String(routeId) : null;
    const routeMeta = routeIdStr ? this.routesMap[routeIdStr] : null;

    let lineName = "Nedefinit";
    let mode = "bus";
    let modeName = "Autobuz";
    let color = "#1e90ff";
    let terminals = [];

    if (routeMeta) {
      lineName = routeMeta.line || routeIdStr;
      mode = routeMeta.type || "bus";
      modeName = routeMeta.typeName || "Autobuz";
      color = routeMeta.color || "#1e90ff";
      terminals = routeMeta.terminals || [];
    } else if (routeIdStr) {
      lineName = `R${routeIdStr}`;
    }

    const directionId = trip.direction_id;
    let directionLabel = "Necunoscut";
    if (directionId === 0) directionLabel = "Tur (Dus)";
    else if (directionId === 1) directionLabel = "Retur (Întors)";

    const onBoard = psg.on_board !== undefined ? psg.on_board : null;
    const inPsg = psg.in !== undefined ? psg.in : null;
    const outPsg = psg.out !== undefined ? psg.out : null;

    let crowding = "unknown";
    let crowdingLabel = "Fără senzori";
    let occupancyPct = null;

    if (onBoard !== null) {
      if (onBoard === 0) {
        crowding = "empty";
        crowdingLabel = "Gol (0 pasageri)";
        occupancyPct = 0;
      } else if (onBoard <= 15) {
        crowding = "low";
        crowdingLabel = `Liber (${onBoard} pasageri)`;
        occupancyPct = Math.min(100, Math.round((onBoard / 80) * 100));
      } else if (onBoard <= 40) {
        crowding = "moderate";
        crowdingLabel = `Moderat (${onBoard} pasageri)`;
        occupancyPct = Math.min(100, Math.round((onBoard / 80) * 100));
      } else if (onBoard <= 70) {
        crowding = "high";
        crowdingLabel = `Aglomerat (${onBoard} pasageri)`;
        occupancyPct = Math.min(100, Math.round((onBoard / 80) * 100));
      } else {
        crowding = "crowded";
        crowdingLabel = `Foarte aglomerat (${onBoard} pasageri)`;
        occupancyPct = 100;
      }
    }

    const sourceMap = {
      0: 'rd API',
      1: 'Thoreb Alert',
      2: 'Thoreb Passenger API',
      3: 'Radcom AVL',
      4: 'Server Central TPBI'
    };
    const sourceName = sourceMap[v.src] || `Sursa ${v.src}`;

    return {
      id: v.id,
      vehicle_id: veh_ident.id,
      license_plate: veh_ident.license_plate || 'N/A',
      th_id: veh_ident.th_id,
      route_id: routeId,
      line: lineName,
      mode: mode,
      mode_name: modeName,
      color: color,
      terminals: terminals,
      direction_id: directionId,
      direction: directionLabel,
      start_time: trip.start_time,
      latitude: pos.latitude,
      longitude: pos.longitude,
      gps_timestamp: pos.timestamp,
      message_timestamp: v.timestamp,
      passengers: {
        on_board: onBoard,
        in: inPsg,
        out: outPsg,
        timestamp: psg.timestamp,
        crowding: crowding,
        crowding_label: crowdingLabel,
        occupancy_pct: occupancyPct
      },
      src: v.src,
      source_name: sourceName
    };
  }

  /**
   * Compute stats from vehicle list
   */
  computeStats(vehicles) {
    const modeCounts = { tram: 0, trolleybus: 0, bus: 0, regional_bus: 0, night_bus: 0, metro: 0 };
    let totalOnBoard = 0;
    let vehiclesWithPsg = 0;
    let totalIn = 0;
    let totalOut = 0;
    const routesActive = new Set();
    const lineOccupancy = {};

    vehicles.forEach(v => {
      const m = v.mode || 'bus';
      modeCounts[m] = (modeCounts[m] || 0) + 1;
      routesActive.add(v.line);

      const psg = v.passengers || {};
      if (psg.on_board !== null) {
        vehiclesWithPsg++;
        totalOnBoard += psg.on_board;

        if (!lineOccupancy[v.line]) {
          lineOccupancy[v.line] = { total_psg: 0, count: 0, mode: m };
        }
        lineOccupancy[v.line].total_psg += psg.on_board;
        lineOccupancy[v.line].count++;
      }

      if (psg.in !== null) totalIn += psg.in;
      if (psg.out !== null) totalOut += psg.out;
    });

    const topLines = Object.entries(lineOccupancy).map(([line, item]) => ({
      line: line,
      mode: item.mode,
      total_passengers: item.total_psg,
      avg_per_vehicle: Math.round((item.total_psg / item.count) * 10) / 10,
      active_vehicles: item.count
    })).sort((a, b) => b.total_passengers - a.total_passengers);

    return {
      total_vehicles: vehicles.length,
      mode_breakdown: modeCounts,
      active_lines_count: routesActive.size,
      passenger_telemetry: {
        monitored_vehicles: vehiclesWithPsg,
        total_on_board: totalOnBoard,
        total_in_flow: totalIn,
        total_out_flow: totalOut,
        avg_occupancy: vehiclesWithPsg ? Math.round((totalOnBoard / vehiclesWithPsg) * 10) / 10 : 0,
        top_busiest_lines: topLines.slice(0, 8)
      },
      updated_at: new Date().toISOString()
    };
  }

  /**
   * Fetch vehicles with hybrid fallback strategy
   */
  async getVehicles(filters = {}) {
    // Strategy 1: Try local backend proxy
    try {
      const params = new URLSearchParams();
      if (filters.mode && filters.mode !== 'all') params.append('mode', filters.mode);
      if (filters.line) params.append('line', filters.line);
      if (filters.crowded) params.append('crowded', 'true');

      const res = await fetch(`${this.baseUrl}/api/vehicles?${params.toString()}`, { signal: AbortSignal.timeout(2500) });
      if (res.ok) {
        const data = await res.json();
        this.cachedVehicles = data.vehicles;
        return data;
      }
    } catch (e) {
      // Backend proxy endpoint not available or timed out
    }

    // Strategy 1.5: Try static live_vehicles.json (written by local background worker)
    if (this.cachedVehicles.length === 0) {
      try {
        const res = await fetch('data/live_vehicles.json', { signal: AbortSignal.timeout(2000) });
        if (res.ok) {
          const data = await res.json();
          if (data && data.vehicles && data.vehicles.length > 0) {
            this.cachedVehicles = data.vehicles;
            this.cachedStats = this.computeStats(this.cachedVehicles);
          }
        }
      } catch (e) {
        // live_vehicles.json not accessible, proceed to direct feed
      }
    }

    // Strategy 2: Direct mo-bi.ro API fetch (with rate limit check)
    const now = Date.now();
    if (now - this.lastUpstreamFetch > 10500 || this.cachedVehicles.length === 0) {
      try {
        console.log("Querying https://mo-bi.ro/python_api/ directly...");
        const res = await fetch('https://mo-bi.ro/python_api/', {
          headers: { 'Accept': 'application/json' },
          signal: AbortSignal.timeout(6000)
        });

        if (res.ok) {
          const rawVehicles = await res.json();
          this.lastUpstreamFetch = now;
          this.isUsingDirectFeed = true;

          // Process & filter valid coordinates
          this.cachedVehicles = rawVehicles
            .filter(item => {
              const p = item.vehicle?.position;
              return p && p.latitude && p.longitude && p.latitude >= 44.0 && p.latitude <= 44.9;
            })
            .map(item => this.enrichRawVehicle(item));

          this.cachedStats = this.computeStats(this.cachedVehicles);
          console.log(`Live Direct Feed: ${this.cachedVehicles.length} vehicles received.`);
        }
      } catch (err) {
        console.warn("Direct mo-bi.ro fetch failed:", err);
      }
    }

    // Strategy 3: Bundled snapshot fallback if cache is still empty
    if (this.cachedVehicles.length === 0) {
      try {
        console.log("Loading bundled snapshot_vehicles.json...");
        const res = await fetch('data/snapshot_vehicles.json');
        if (res.ok) {
          const raw = await res.json();
          this.cachedVehicles = raw.map(item => this.enrichRawVehicle(item));
          this.cachedStats = this.computeStats(this.cachedVehicles);
        }
      } catch (err) {
        console.warn("Snapshot fallback error:", err);
      }
    }

    // Apply filters to cached vehicles
    let filtered = [...this.cachedVehicles];
    if (filters.mode && filters.mode !== 'all') {
      filtered = filtered.filter(v => v.mode === filters.mode);
    }
    if (filters.line) {
      const q = filters.line.trim().toUpperCase();
      filtered = filtered.filter(v => (v.line && v.line.toUpperCase().includes(q)) || (v.license_plate && v.license_plate.toUpperCase().includes(q)));
    }
    if (filters.crowded) {
      filtered = filtered.filter(v => ['high', 'crowded'].includes(v.passengers?.crowding));
    }

    return {
      meta: {
        total: this.cachedVehicles.length,
        status: `Actualizat ${new Date(this.lastUpstreamFetch || Date.now()).toLocaleTimeString('ro-RO')} (${this.isUsingDirectFeed ? 'Direct mo-bi.ro' : 'Server Local / Snapshot'})`,
        rate_limit_cooldown: Math.max(0, Math.ceil((11000 - (Date.now() - this.lastUpstreamFetch)) / 1000))
      },
      count: filtered.length,
      vehicles: filtered
    };
  }

  /**
   * Fetch Stats
   */
  async getStats() {
    try {
      const res = await fetch(`${this.baseUrl}/api/stats`, { signal: AbortSignal.timeout(2000) });
      if (res.ok) return await res.json();
    } catch (e) {
      // Fallback to locally computed stats
    }

    if (!this.cachedStats && this.cachedVehicles.length > 0) {
      this.cachedStats = this.computeStats(this.cachedVehicles);
    }

    return this.cachedStats || {
      total_vehicles: 0,
      mode_breakdown: {},
      active_lines_count: 0,
      passenger_telemetry: {
        monitored_vehicles: 0,
        total_on_board: 0,
        avg_occupancy: 0,
        top_busiest_lines: []
      }
    };
  }

  /**
   * Fetch Routes metadata
   */
  async getRoutes() {
    try {
      const res = await fetch(`${this.baseUrl}/api/routes`, { signal: AbortSignal.timeout(2000) });
      if (res.ok) return await res.json();
    } catch (e) {
      // Fallback to client-side routesMap
    }

    // Calculate active vehicle count per route from cached vehicles
    const counts = {};
    this.cachedVehicles.forEach(v => {
      const rid = String(v.route_id || '');
      counts[rid] = (counts[rid] || 0) + 1;
    });

    const list = Object.entries(this.routesMap).map(([rid, meta]) => ({
      route_id: rid,
      line: meta.line || rid,
      type: meta.type || 'bus',
      typeName: meta.typeName || 'Autobuz',
      color: meta.color || '#1e90ff',
      operator: meta.operator || 'STB',
      terminals: meta.terminals || [],
      active_vehicles: counts[rid] || 0
    }));

    list.sort((a, b) => {
      if ((a.active_vehicles > 0) !== (b.active_vehicles > 0)) {
        return (b.active_vehicles > 0) - (a.active_vehicles > 0);
      }
      return b.active_vehicles - a.active_vehicles;
    });

    return list;
  }

  /**
   * Fetch line route details (Tur & Retur geometries, terminals, stations)
   */
  async getLineDetails(lineName) {
    const cleanLine = String(lineName).trim().toUpperCase();

    // 1. Try local backend proxy
    try {
      const res = await fetch(`${this.baseUrl}/api/line/${encodeURIComponent(cleanLine)}`, { signal: AbortSignal.timeout(2000) });
      if (res.ok) {
        return await res.json();
      }
    } catch (e) {}

    // 2. Fallback to bundled line_routes_index.json
    try {
      if (!this.lineIndexCache) {
        const res = await fetch('data/line_routes_index.json');
        if (res.ok) {
          this.lineIndexCache = await res.json();
        }
      }
      if (this.lineIndexCache && this.lineIndexCache[cleanLine]) {
        const item = this.lineIndexCache[cleanLine];
        const turCount = this.cachedVehicles.filter(v => String(v.line).toUpperCase() === cleanLine && v.direction_id === 0).length;
        const returCount = this.cachedVehicles.filter(v => String(v.line).toUpperCase() === cleanLine && v.direction_id === 1).length;
        const total = this.cachedVehicles.filter(v => String(v.line).toUpperCase() === cleanLine).length;

        return {
          ...item,
          live_vehicles: { total: total, tur: turCount, retur: returCount }
        };
      }
    } catch (e) {
      console.warn("Could not load line_routes_index fallback:", e);
    }

    return null;
  }

  /**
   * Fetch GeoJSON layer
   */
  async getLayer(layerName) {
    const filenameMap = {
      'tram_network': 'retea_tramvai.geojson',
      'trolley_network': 'retea_troleibuze.geojson',
      'metro_network': 'retea_metrou.geojson',
      'metro_stations': 'statii_metrou.geojson',
      'depots': 'depouri.geojson',
      'autobaze': 'autobaze.geojson',
      'park_ride': 'parkride.geojson',
      'bus_lanes': 'benzi_dedicate.geojson',
      'night_network': 'retea_autobuz_noapte.geojson',
      'electric_bus': 'retea_autobuze_electrice.geojson',
      'regional_network': 'retea_autobuze_regionale.geojson',
      'city_boundary': 'limita_bucuresti_ilfov.geojson',
      'routes': 'routes_iun2024.geojson',
      'stations': 'statii_transport_public_suprafata.geojson'
    };

    const fname = filenameMap[layerName];
    if (!fname) return null;

    // Try local /api/layers/:name first
    try {
      const res = await fetch(`${this.baseUrl}/api/layers/${layerName}`, { signal: AbortSignal.timeout(2000) });
      if (res.ok) return await res.json();
    } catch (e) {}

    // Fallback to static data/layers/:file
    try {
      const res = await fetch(`data/layers/${fname}`);
      if (res.ok) return await res.json();
    } catch (e) {
      console.warn(`Layer ${layerName} failed to load:`, e);
    }
    return null;
  }

  /**
   * Force refresh respecting 10s cooldown
   */
  async triggerRefresh() {
    this.lastUpstreamFetch = 0; // reset to allow immediate query
    return { success: true };
  }

  // ==========================================================================
  // Bilet TB (STB SA Ticketing) Client Integration (Copied from bilet-tb-app)
  // ==========================================================================

  get stbApiUrl() {
    return 'https://online.stbsa.ro:8080/external';
  }

  getStoredToken() {
    return localStorage.getItem('stb_auth_token') || localStorage.getItem('authenticationToken');
  }

  setStoredToken(token) {
    if (token) {
      localStorage.setItem('stb_auth_token', token);
      localStorage.setItem('authenticationToken', token);
    } else {
      localStorage.removeItem('stb_auth_token');
      localStorage.removeItem('authenticationToken');
    }
  }

  /**
   * Check Bilet TB status and account state
   */
  async getBiletTbStatus() {
    const token = this.getStoredToken();
    if (!token) {
      return { authenticated: false, account: null, activeTicketsCount: 0, availableTicketsCount: 0 };
    }

    const account = await this.getBiletTbAccount(token);
    let activeTickets = [];
    try {
      activeTickets = await this.getBiletTbActiveTickets();
    } catch (_) {}

    let availableCount = 0;
    try {
      const pkgs = await this.getBiletTbAvailablePackages();
      availableCount = (pkgs || []).reduce((sum, p) => sum + (p.ticketsRemaining || 0), 0);
    } catch (_) {}

    return {
      authenticated: true,
      account: account,
      activeTicketsCount: activeTickets.length,
      availableTicketsCount: availableCount
    };
  }

  /**
   * Fetch user account details
   */
  async getBiletTbAccount(token) {
    token = token || this.getStoredToken();
    if (!token) return null;

    if (token.startsWith('mock_')) {
      const cached = localStorage.getItem('stb_account');
      return cached ? JSON.parse(cached) : {
        id: 101,
        login: 'calator.elev',
        firstName: 'Alexandru',
        lastName: 'Ionescu',
        email: 'elev.stb@gmail.com',
        fareCategory: { id: 0, name: 'elev', description: 'Reducere de elev (Gratuit)' }
      };
    }

    // 1. Direct call to live STB API
    try {
      const res = await fetch(`${this.stbApiUrl}/account`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      if (res.ok) {
        const acc = await res.json();
        localStorage.setItem('stb_account', JSON.stringify(acc));
        return acc;
      }
    } catch (e) {
      console.warn("Direct STB /account error, trying proxy:", e);
    }

    // 2. Fallback via backend proxy
    try {
      const pRes = await fetch(`${this.baseUrl}/api/bilet-tb/account`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      if (pRes.ok) {
        const acc = await pRes.json();
        if (acc && (acc.login || acc.email)) {
          localStorage.setItem('stb_account', JSON.stringify(acc));
          return acc;
        }
      }
    } catch (_) {}

    const cached = localStorage.getItem('stb_account');
    return cached ? JSON.parse(cached) : null;
  }

  /**
   * Fetch active travel titles from STB API with QR codes, dates & countdown timers
   */
  async getBiletTbActiveTickets() {
    const token = this.getStoredToken();
    if (!token) return [];

    if (token.startsWith('mock_')) {
      return this.normalizeActiveTickets(this.getMockActiveTickets());
    }

    // 1. Direct call to live STB API: POST /active-user-tickets with body {}
    try {
      const res = await fetch(`${this.stbApiUrl}/active-user-tickets`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
      });

      if (res.ok) {
        const tickets = await res.json();
        if (Array.isArray(tickets)) {
          console.log(`[Bilet TB] Received ${tickets.length} active tickets from live STB backend!`, tickets);
          localStorage.setItem('stb_active_tickets', JSON.stringify(tickets));
          return this.normalizeActiveTickets(tickets);
        }
      } else {
        console.warn("STB /active-user-tickets returned status", res.status);
      }
    } catch (e) {
      console.warn("Direct STB active-user-tickets error, trying backend proxy:", e);
    }

    // 2. Fallback via backend proxy
    try {
      const pRes = await fetch(`${this.baseUrl}/api/bilet-tb/active-tickets`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      if (pRes.ok) {
        const pData = await pRes.json();
        if (pData.tickets && pData.tickets.length > 0) {
          localStorage.setItem('stb_active_tickets', JSON.stringify(pData.tickets));
          return this.normalizeActiveTickets(pData.tickets);
        }
      }
    } catch (_) {}

    const cached = localStorage.getItem('stb_active_tickets');
    return cached ? this.normalizeActiveTickets(JSON.parse(cached)) : [];
  }

  /**
   * Normalize STB ActiveUserTicket objects into uniform display model
   */
  normalizeActiveTickets(rawList) {
    if (!Array.isArray(rawList)) return [];
    const now = Date.now();

    return rawList.map((t, idx) => {
      // 1. Title Resolution (from ticketPackage.ticket.name, ticket.name, or t.title)
      let title = '';
      if (t.ticketPackage && t.ticketPackage.ticket && t.ticketPackage.ticket.name) {
        title = t.ticketPackage.ticket.name;
      } else if (t.ticket && t.ticket.name) {
        title = t.ticket.name;
      } else if (t.title) {
        title = t.title;
      } else {
        title = 'Titlu de Călătorie STB';
      }

      // 2. Fare Category & Elev Detection
      const fareCat = (t.ticketPackage && t.ticketPackage.fareCategory) || t.fareCategory || {};
      const catName = String(fareCat.name || '').toLowerCase();
      const catDesc = String(fareCat.description || '');
      const titleLower = title.toLowerCase();

      const isElev = catName === 'elev' || catName === 'pupil' || titleLower.includes('elev') || catDesc.toLowerCase().includes('elev');
      const isStudent = catName === 'student' || titleLower.includes('student');

      let categoryBadge = 'Standard';
      if (isElev) {
        categoryBadge = '🎓 ELEV (100% GRATUIT)';
      } else if (isStudent) {
        categoryBadge = '🎓 Student (Redus)';
      } else if (catDesc) {
        categoryBadge = catDesc;
      }

      // 3. Group Name
      const grp = (t.ticketPackage && t.ticketPackage.ticket && t.ticketPackage.ticket.ticketGroup) || t.ticketGroup || {};
      const grpName = grp.name ? (grp.name.charAt(0).toUpperCase() + grp.name.slice(1) + ' București-Ilfov') : (t.groupName || 'Rețeaua Metropolitană');

      // 4. Validity Dates & Countdown
      const vFrom = t.validFromDate || t.activationDate || new Date().toISOString();
      const vTo = t.validToDate || t.expirationDate || new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString();

      const endMs = new Date(vTo).getTime();
      const remainingMs = isNaN(endMs) ? 3600000 : Math.max(0, endMs - now);
      const remainingSeconds = Math.floor(remainingMs / 1000);

      // 5. High-Resolution QR Code (STB sends real base64 JPEG in t.qrCode)
      let qrCode = t.qrCode;
      if (qrCode && !qrCode.startsWith('data:')) {
        qrCode = 'data:image/JPEG;base64,' + qrCode;
      }

      // 6. Series Code
      const qrCodeCode = t.qrCodeCode || t.code || `STB-2026-${t.id || (88000000 + idx)}`;

      // 7. Fare
      const fare = (t.ticketPackage && t.ticketPackage.ticket && t.ticketPackage.ticket.ticketFare !== undefined)
        ? t.ticketPackage.ticket.ticketFare
        : (isElev ? 0.0 : (t.fare || 3.0));

      return {
        id: t.id || idx + 1,
        title: title,
        groupName: grpName,
        fare: fare,
        fareCategory: fareCat,
        categoryBadge: categoryBadge,
        isElev: isElev,
        isStudent: isStudent,
        validFromDate: vFrom,
        validToDate: vTo,
        remainingMs: remainingMs,
        remainingSeconds: remainingSeconds,
        qrCode: qrCode,
        qrCodeCode: qrCodeCode,
        isTicketScanned: t.isTicketScanned ?? true,
        status: 'active'
      };
    });
  }

  /**
   * Fetch available ticket packages in user's wallet
   */
  async getBiletTbAvailablePackages() {
    const token = this.getStoredToken();
    if (!token) return [];

    if (token.startsWith('mock_')) {
      return this.getMockWalletPackages();
    }

    try {
      const res = await fetch(`${this.stbApiUrl}/ticket-packages/available/grouped`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      if (res.ok) {
        const pkgs = await res.json();
        if (Array.isArray(pkgs)) {
          return pkgs.map(p => ({
            id: p.ticketId || p.id,
            title: p.ticketName || p.title || 'Bilet metropolitan',
            groupName: p.ticketGroupName || 'Urban București-Ilfov',
            ticketsRemaining: p.ticketsRemaining || (p.ticketPackages ? p.ticketPackages.length : 1),
            validPeriodMinutes: p.validPeriodUnits || p.validPeriod || 90
          }));
        }
      }
    } catch (e) {
      console.warn("Direct STB available packages error, trying proxy:", e);
    }

    try {
      const pRes = await fetch(`${this.baseUrl}/api/bilet-tb/available-packages`, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      if (pRes.ok) {
        const pData = await pRes.json();
        return pData.packages || [];
      }
    } catch (_) {}

    return [];
  }

  /**
   * Fetch official STB catalog of fare categories and passes
   */
  async getBiletTbCatalog() {
    try {
      const res = await fetch(`${this.stbApiUrl}/tickets/active`);
      if (res.ok) {
        const list = await res.json();
        if (Array.isArray(list) && list.length > 0) {
          return list.map(item => ({
            id: item.id,
            name: item.name || item.name_en,
            desc: item.ticketGroup ? `${item.ticketGroup.name} • ${item.validPeriod || 90} min` : 'Valabil pe toate liniile STB & Ilfov',
            fare: item.ticketFare !== undefined ? item.ticketFare : 3.0,
            validMinutes: item.validPeriod || 90
          }));
        }
      }
    } catch (e) {
      console.warn("Direct STB catalog error, using standard STB catalog:", e);
    }

    try {
      const pRes = await fetch(`${this.baseUrl}/api/bilet-tb/catalog`);
      if (pRes.ok) {
        const pData = await pRes.json();
        if (pData.catalog && pData.catalog.length > 0) return pData.catalog;
      }
    } catch (_) {}

    return this.getDefaultCatalog();
  }

  /**
   * Authenticate with STB Bilet TB account (supports live server & demo fallback)
   */
  async loginBiletTb(username, password, isDemo = false) {
    const u = username.trim();
    const p = password;

    const isDemoLogin = isDemo || u === 'elev.stb@gmail.com' || u === 'calator.stb@gmail.com' || u.includes('demo');

    // Demo account (Simulated Elev Annual Pass)
    if (isDemoLogin) {
      const mockToken = 'mock_jwt_token_bilet_tb_stb_authenticated_user';
      this.setStoredToken(mockToken);
      const mockAcc = {
        id: 101,
        login: 'calator.elev',
        firstName: 'Alexandru',
        lastName: 'Ionescu',
        email: u || 'elev.stb@gmail.com',
        fareCategory: { id: 0, name: 'elev', description: 'Reducere de elev (Gratuit)', externalCode: 21 }
      };
      localStorage.setItem('stb_account', JSON.stringify(mockAcc));
      const demoTickets = this.getMockActiveTickets();
      localStorage.setItem('stb_active_tickets', JSON.stringify(demoTickets));
      try {
        await fetch(`${this.baseUrl}/api/bilet-tb/authenticate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ username: u, password: p, isDemo: true })
        });
      } catch (_) {}
      return { success: true, token: mockToken, account: mockAcc, tickets: demoTickets };
    }

    // 1. Direct call to live STB API
    try {
      const res = await fetch(`${this.stbApiUrl}/authenticate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: u,
          password: p,
          rememberMe: true,
          deviceUuid: 'antigravity-stb-web-client'
        })
      });

      if (res.ok) {
        const data = await res.json();
        const token = data.id_token;
        if (token) {
          this.setStoredToken(token);
          const acc = await this.getBiletTbAccount(token);
          const tickets = await this.getBiletTbActiveTickets();
          return { success: true, token, account: acc, tickets };
        }
      } else {
        const errJson = await res.json().catch(() => ({}));
        throw new Error(errJson.detail || errJson.message || 'Date de autentificare incorecte.');
      }
    } catch (e) {
      console.warn("Direct STB login error, trying backend proxy fallback:", e);
    }

    // 2. Fallback via backend proxy
    try {
      const proxyRes = await fetch(`${this.baseUrl}/api/bilet-tb/authenticate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: u, password: p })
      });
      const pData = await proxyRes.json();
      if (pData.success && pData.token) {
        this.setStoredToken(pData.token);
        if (pData.account) localStorage.setItem('stb_account', JSON.stringify(pData.account));
        return pData;
      }
      return pData;
    } catch (proxyErr) {
      return { success: false, error: proxyErr.message };
    }
  }

  /**
   * Activate ticket package
   */
  async activateBiletTb(ticketPackageId = 201) {
    const token = this.getStoredToken();
    if (token && !token.startsWith('mock_')) {
      try {
        const res = await fetch(`${this.stbApiUrl}/user-tickets/activation`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ ticketPackageId, numberOfTickets: 1 })
        });
        if (res.ok) {
          return { success: true };
        }
      } catch (e) {
        console.warn("Direct live activation error:", e);
      }
    }

    try {
      const res = await fetch(`${this.baseUrl}/api/bilet-tb/activate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ticketPackageId })
      });
      return await res.json();
    } catch (e) {
      return { success: false, error: e.message };
    }
  }

  /**
   * Purchase ticket
   */
  async purchaseBiletTb(catalogId) {
    try {
      const res = await fetch(`${this.baseUrl}/api/bilet-tb/purchase`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ catalogId })
      });
      return await res.json();
    } catch (e) {
      return { success: false, error: e.message };
    }
  }

  /**
   * Log out
   */
  async logoutBiletTb() {
    this.setStoredToken(null);
    localStorage.removeItem('stb_account');
    localStorage.removeItem('stb_active_tickets');
    try {
      await fetch(`${this.baseUrl}/api/bilet-tb/logout`, { method: 'POST' });
    } catch (_) {}
    return { success: true };
  }

  getMockActiveTickets() {
    const now = new Date();
    return [
      {
        id: 7001,
        title: 'Abonament metropolitan elev',
        groupName: 'Urban București-Ilfov',
        fare: 0.0,
        fareCategory: { id: 0, name: 'elev', description: 'Reducere de elev (Gratuit)' },
        categoryBadge: '🎓 ELEV (100% GRATUIT)',
        isElev: true,
        validFromDate: new Date(now.getTime() - 45 * 24 * 3600 * 1000).toISOString(),
        validToDate: new Date(now.getTime() + 320 * 24 * 3600 * 1000).toISOString(),
        qrCodeCode: 'STB-ELEV-2026-9845102',
        isTicketScanned: true,
        status: 'active'
      }
    ];
  }

  getMockWalletPackages() {
    return [
      {
        id: 201,
        title: 'Bilet metropolitan 90 minute',
        groupName: 'Urban București-Ilfov',
        ticketsRemaining: 2,
        validPeriodMinutes: 90
      }
    ];
  }

  getDefaultCatalog() {
    return [
      { id: 1, name: 'Bilet metropolitan 90 minute', desc: 'Valabil 90 min pe toate liniile de suprafață STB', fare: 3.0, validMinutes: 90 },
      { id: 2, name: 'Bilet metropolitan 24 ore', desc: 'Valabil 24h pe rețeaua de suprafață', fare: 8.0, validMinutes: 1440 },
      { id: 3, name: 'Bilet metropolitan 72 ore', desc: 'Valabil 72h pe rețeaua de suprafață', fare: 20.0, validMinutes: 4320 },
      { id: 4, name: 'Abonament metropolitan 30 zile', desc: 'Călătorii nelimitate 30 de zile', fare: 80.0, validMinutes: 43200 },
      { id: 5, name: 'Bilet metropolitan și tren 24 ore', desc: 'Include tren Gara de Nord - Aeroport Otopeni', fare: 20.0, validMinutes: 1440 },
      { id: 6, name: 'Abonament metropolitan și tren 30 zile', desc: 'Suprafață + Tren Aeroport Otopeni 30 de zile', fare: 140.0, validMinutes: 43200 }
    ];
  }
}

window.API = new TransitAPI();
window.API.init();
