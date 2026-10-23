# 🚎 Bucharest Public Transport - Interactive Live Map & Passenger Telemetry

An interactive, real-time web application for exploring public transport in Bucharest and Ilfov county, powered by official open data from **TPBI** (Transport Public București - Ilfov) and **STB** (Societatea de Transport București).

![Bucharest Public Transport](https://img.shields.io/badge/Vehicles_Tracked-~1400_Live-06b6d4?style=for-the-badge)
![Monitored Passenger Telemetry](https://img.shields.io/badge/Passenger_Sensors-650+_Vehicles-10b981?style=for-the-badge)
![Lines Mapped](https://img.shields.io/badge/Lines_Mapped-268_Routes-f59e0b?style=for-the-badge)
![Zero External Dependencies](https://img.shields.io/badge/Dependencies-Zero_(Python3_StdLib)-8b5cf6?style=for-the-badge)

---

## 🚀 Quick Start

The app runs on Python 3 with **zero third-party dependencies** (`urllib`, `http.server`, `threading`, `json`):

```bash
# 1. From the repository root, enter the prototype directory
cd tools/web-prototype-and-data

# 2. Launch the server
./run.sh
# or: python3 app.py
```

Open your browser at: **`http://localhost:8080`**

---

## 📡 Open Data Endpoints & Technical Deep Dive

During development, extensive research was conducted on the data sources provided:

### 1. Primary Live Feed (`https://mo-bi.ro/python_api/`)
- **Rate Limit:** **Strictly 1 query per 10 seconds per IP address.** Exceeding this returns `HTTP 429 Too Many Requests`.
- **CORS Support:** The endpoint provides `access-control-allow-origin: *`, enabling direct client fetch or proxying.
- **Active Fleet:** Transmits live coordinates and telemetry for **~1,350 to 1,450 vehicles** continuously.
- **Data Formats & Endpoints:**
  - `GET https://mo-bi.ro/python_api/` — Complete fleet snapshot (GTFS-RT JSON format with vehicle positions and APC).
  - `GET https://mo-bi.ro/python_api/psg` — Filtered subset containing vehicles with active passenger counting sensors.
  - `GET https://mo-bi.ro/python_api/openapi.yaml` — Official OpenAPI specification.

### 2. Upstream Telemetry Sources (`src` field)
The feed integrates multiple dispatching and telemetry systems:
- `src: 0` — **rd API** (Radcom dispatching system)
- `src: 1` — **Thoreb Alert** (on-board event alerts)
- `src: 2` — **Thoreb Passenger API** (Automated Passenger Counting sensors)
- `src: 3` — **Radcom AVL** (Automatic Vehicle Location GPS)
- `src: 4` — **Server Central TPBI** (unified regional aggregator)

### 3. Automated Passenger Counting (APC)
For ~650 modern vehicles (Otokar Kent, Mercedes-Benz Citaro Hybrid, Solaris Trollino, Astra Imperio Metropolitan):
- `on_board`: Current number of passengers on board.
- `in`: Passengers who boarded at the most recent stop.
- `out`: Passengers who alighted at the most recent stop.
- `timestamp`: Timestamp of the sensor reading.

### 4. Route IDs vs Human-Readable Lines
In the raw API, `route_id` is an internal database identifier (e.g., `route_id: 68` is Tram 1, `67` is Tram 10, `84` is Trolley 61, `75` is Trolley 69, `968` is Metro M1).
Our application maps **268 lines (100% of the active transit network)** via `data/routes_map.json`:
- **Trams (Liniile 1, 10, 21, 25, 32, 41, etc.):** Rendered in bright yellow/amber (`#eab308`).
- **Trolleybuses (Liniile 61, 62, 69, 70, 79, 85, 86, 90, 93, 97, etc.):** Rendered in emerald green (`#10b981`).
- **Urban Buses (Liniile 100, 104, 137, 178, 282, 301, 335, 381, etc.):** Rendered in dodger blue (`#1e90ff`).
- **Night Buses (Liniile N101 – N122):** Rendered in indigo (`#6366f1`).
- **Regional Buses (Liniile 400 – 487):** Rendered in purple (`#8b5cf6`).
- **Metrorex (M1, M2, M3, M4, M5):** Rendered in crimson (`#dc2626`).

---

## 🏗️ Architecture & Rate Limit Solution

To ensure strict compliance with the **1 request per 10 seconds** rate limit while supporting multiple browser tabs:

```
                  ┌──────────────────────────────────────────────┐
                  │          mo-bi.ro Open Data API             │
                  │ (Rate limited: max 1 query / 10s per IP)     │
                  └──────────────────────┬───────────────────────┘
                                         │  (Polls every 12s via proxy)
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │         Python Backend Cache (app.py)        │
                  │  - Threading HTTPServer                      │
                  │  - Background daemon thread (12s cycle)      │
                  │  - 268-route dictionary enrichment           │
                  │  - Crowding calculation & telemetry stats    │
                  │  - Writes public/data/live_vehicles.json     │
                  └──────────────────────┬───────────────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
┌─────────────────┐            ┌───────────────────┐            ┌─────────────────┐
│ Browser Client  │            │  Browser Client   │            │ Static Fallback │
│  (Map UI)       │            │   (Stats Tab)     │            │  (File Mode)    │
└─────────────────┘            └───────────────────┘            └─────────────────┘
```

1. **In-Memory Caching Proxy:** `app.py` runs a background worker polling every 12 seconds (safely over the 10s threshold).
2. **Instant Response:** Client queries to `/api/vehicles` return immediately from cache with 0ms upstream latency.
3. **Resilient Hybrid Fallback:** If the backend proxy is stopped, the client automatically falls back to:
   - Freshly generated `live_vehicles.json`
   - Direct `mo-bi.ro` API querying with client-side rate limiting
   - Offline snapshot (`snapshot_vehicles.json`)

---

## 🎨 Interactive Features

1. **Real-time Map with Custom DivIcons:**
   - Visual badges showing line numbers and mode icons.
   - Pulsing occupancy halos (green = low, amber = moderate, red = crowded).
   - Smooth position updates every 12 seconds with countdown timer.
2. **Vehicle Inspector HUD:**
   - Click any vehicle to inspect license plate, line, direction (Tur/Retur), data source, passenger count, boarding/alighting deltas, and occupancy meter.
   - **"Urmărește vehicul" (Follow Vehicle):** Automatically follows vehicle across the city.
   - **"Afișează traseu" (Show Route):** Highlights the complete line path on the map.
3. **Comprehensive Filter Chips & Instant Search:**
   - Quick filters: Toate, Tramvai, Troleibuz, Autobuz, Regio, Noapte, Aglomerate (High Crowding).
   - Real-time search bar matching line number or license plate.
4. **4-Tab Sidebar Panel:**
   - **Linii (Lines):** All 268 lines with live vehicle counts and click-to-filter.
   - **Vehicule (Vehicles):** Scrollable list of active vehicles with live occupancy tags.
   - **Pasageri (Passenger Analytics):** Live telemetry KPIs, net flow rates, and ranking of top 8 busiest lines.
   - **Straturi (Infrastructure Layers):** Toggle tram tracks, trolleybus overhead lines, metro network, metro stations, dedicated bus lanes, night network, regional lines, depots, and park & rides.
5. **Geolocation (GPS):** Center on your live GPS location in Bucharest with accuracy radius.
6. **Dark / Light Theme Toggle:** Clean switcher adapting both UI and map tile styles (Carto Dark Matter & Voyager).

---

## 🗺️ Included GeoJSON Layers (from `BucharestOpenData/RealTimeMap`)

All GeoJSON layers are bundled in `public/data/layers/`:
- `retea_tramvai.geojson` — Complete tram track infrastructure
- `retea_troleibuze.geojson` — Trolleybus catenary overhead lines
- `retea_metrou.geojson` & `statii_metrou.geojson` — Metrorex lines M1-M5 and stations
- `benzi_dedicate.geojson` — Dedicated bus and transit lanes
- `retea_autobuz_noapte.geojson` — Night bus routes
- `retea_autobuze_electrice.geojson` — Electric bus lines
- `retea_autobuze_regionale.geojson` — Ilfov regional bus network
- `depouri.geojson` & `autobaze.geojson` — Tram depots and bus garages
- `parkride.geojson` — Terminal park-and-ride facilities
- `statii_transport_public_suprafata.geojson` — Surface transit stops
- `routes_iun2024.geojson` — Complete geometric route paths

---

## 📄 License & Credits
- **Data Provider:** [TPBI (Asociația de Dezvoltare Intercomunitară pentru Transport Public București - Ilfov)](https://tpbi.ro) & [mo-bi.ro](https://mo-bi.ro)
- **Map Library:** [Leaflet.js](https://leafletjs.com/)
- **Tile Providers:** OpenStreetMap & CARTO
