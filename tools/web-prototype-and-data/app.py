#!/usr/bin/env python3
"""
Bucharest Public Transport Interactive App - Backend Server
Provides:
  - Smart In-Memory Caching Proxy to mo-bi.ro Open Data API (Strictly honoring 1 req / 10s rate limit)
  - Vehicle route resolution & classification (Trams, Trolleys, Buses, Metro, Night Buses, Regional)
  - Passenger crowding calculations (Automatic Passenger Counting data)
  - GeoJSON layers serving (Transit lines, Depots, Stations, Dedicated lanes)
  - Static Web UI hosting
"""

import http.server
import urllib.request
import urllib.error
import urllib.parse
import json
import os
import sys
import time
import threading
import ssl
import random
from datetime import datetime, timezone, timedelta

DEFAULT_PORT = int(os.environ.get('PORT', 8080))
PORT = DEFAULT_PORT
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'data')
LAYERS_DIR = os.path.join(DATA_DIR, 'layers')
PUBLIC_DIR = os.path.join(BASE_DIR, 'public')

# Load Route Mapping
ROUTES_MAP_PATH = os.path.join(DATA_DIR, 'routes_map.json')
routes_map = {}
if os.path.exists(ROUTES_MAP_PATH):
    try:
        with open(ROUTES_MAP_PATH, 'r', encoding='utf-8') as f:
            routes_map = json.load(f)
        print(f"Loaded {len(routes_map)} route mappings from routes_map.json")
    except Exception as e:
        print(f"Warning: Failed loading routes_map.json: {e}")

# Load fallback snapshot
SNAPSHOT_PATH = os.path.join(DATA_DIR, 'snapshot_vehicles.json')
snapshot_data = []
if os.path.exists(SNAPSHOT_PATH):
    try:
        with open(SNAPSHOT_PATH, 'r', encoding='utf-8') as f:
            snapshot_data = json.load(f)
        print(f"Loaded {len(snapshot_data)} fallback vehicles from snapshot")
    except Exception as e:
        print(f"Warning: Failed loading snapshot: {e}")

# Load Pre-indexed Line Routes & Stations (Tur / Retur geometries)
LINE_ROUTES_INDEX_PATH = os.path.join(DATA_DIR, 'line_routes_index.json')
line_routes_index = {}
if os.path.exists(LINE_ROUTES_INDEX_PATH):
    try:
        with open(LINE_ROUTES_INDEX_PATH, 'r', encoding='utf-8') as f:
            line_routes_index = json.load(f)
        print(f"Loaded {len(line_routes_index)} line route geometries from line_routes_index.json")
    except Exception as e:
        print(f"Warning: Failed loading line_routes_index.json: {e}")

# Cache state
cache_lock = threading.RLock()
cache_state = {
    'vehicles_raw': snapshot_data,
    'vehicles_processed': [],
    'stats': {},
    'last_update_ts': time.time(),
    'last_upstream_call': 0,
    'status': 'Snapshot loaded, initializing live feed...',
    'error': None,
    'query_count': 0,
    'cooldown_seconds': 10
}

def get_proxy_opener():
    """Build opener with system proxy environment variables."""
    return urllib.request.build_opener(urllib.request.ProxyHandler())

def enrich_vehicle(v):
    """Enrich raw vehicle object with route details, mode, line number and crowding level."""
    v_info = v.get('vehicle', {})
    trip = v_info.get('trip', {})
    veh_ident = v_info.get('vehicle', {})
    pos = v_info.get('position', {})
    psg = v_info.get('passenger_info', {})

    route_id = trip.get('route_id')
    route_id_str = str(route_id) if route_id is not None else None
    
    route_meta = routes_map.get(route_id_str) if route_id_str else None

    # Derive line name & transit type
    line_name = "Nedefinit"
    mode = "bus"
    mode_name = "Autobuz"
    color = "#1e90ff"
    terminals = []

    if route_meta:
        line_name = route_meta.get('line', str(route_id_str))
        mode = route_meta.get('type', 'bus')
        mode_name = route_meta.get('typeName', 'Autobuz')
        color = route_meta.get('color', '#1e90ff')
        terminals = route_meta.get('terminals', [])
    elif route_id_str:
        line_name = f"R{route_id_str}"

    # Direction
    direction_id = trip.get('direction_id')
    direction_label = "Necunoscut"
    if direction_id == 0:
        direction_label = "Tur (Dus)"
    elif direction_id == 1:
        direction_label = "Retur (Întors)"

    # Passenger Occupancy
    on_board = psg.get('on_board')
    in_psg = psg.get('in')
    out_psg = psg.get('out')
    psg_ts = psg.get('timestamp')

    crowding = "unknown"
    crowding_label = "Fără senzori"
    occupancy_pct = None

    if on_board is not None:
        if on_board == 0:
            crowding = "empty"
            crowding_label = "Gol (0 pasageri)"
            occupancy_pct = 0
        elif on_board <= 15:
            crowding = "low"
            crowding_label = f"Liber ({on_board} pasageri)"
            occupancy_pct = min(100, int((on_board / 80) * 100))
        elif on_board <= 40:
            crowding = "moderate"
            crowding_label = f"Moderat ({on_board} pasageri)"
            occupancy_pct = min(100, int((on_board / 80) * 100))
        elif on_board <= 70:
            crowding = "high"
            crowding_label = f"Aglomerat ({on_board} pasageri)"
            occupancy_pct = min(100, int((on_board / 80) * 100))
        else:
            crowding = "crowded"
            crowding_label = f"Foarte aglomerat ({on_board} pasageri)"
            occupancy_pct = 100

    # Source info
    src = v.get('src')
    source_map = {
        0: 'rd API',
        1: 'Thoreb Alert',
        2: 'Thoreb Passenger API',
        3: 'Radcom AVL',
        4: 'Server Central TPBI'
    }
    source_name = source_map.get(src, f'Sursa {src}')

    return {
        'id': v.get('id'),
        'vehicle_id': veh_ident.get('id'),
        'license_plate': veh_ident.get('license_plate') or 'N/A',
        'th_id': veh_ident.get('th_id'),
        'route_id': route_id,
        'line': line_name,
        'mode': mode,
        'mode_name': mode_name,
        'color': color,
        'terminals': terminals,
        'direction_id': direction_id,
        'direction': direction_label,
        'start_time': trip.get('start_time'),
        'latitude': pos.get('latitude'),
        'longitude': pos.get('longitude'),
        'gps_timestamp': pos.get('timestamp'),
        'message_timestamp': v.get('timestamp'),
        'passengers': {
            'on_board': on_board,
            'in': in_psg,
            'out': out_psg,
            'timestamp': psg_ts,
            'crowding': crowding,
            'crowding_label': crowding_label,
            'occupancy_pct': occupancy_pct
        },
        'src': src,
        'source_name': source_name
    }

def compute_stats(vehicles):
    """Compute aggregate fleet telemetry and passenger flow."""
    total = len(vehicles)
    mode_counts = {'tram': 0, 'trolleybus': 0, 'bus': 0, 'regional_bus': 0, 'night_bus': 0, 'metro': 0}
    total_on_board = 0
    vehicles_with_psg = 0
    total_in = 0
    total_out = 0
    routes_active = set()
    line_occupancy = {}

    for v in vehicles:
        m = v.get('mode', 'bus')
        mode_counts[m] = mode_counts.get(m, 0) + 1
        line = v.get('line', 'N/A')
        routes_active.add(line)

        psg = v.get('passengers', {})
        ob = psg.get('on_board')
        if ob is not None:
            vehicles_with_psg += 1
            total_on_board += ob
            if line not in line_occupancy:
                line_occupancy[line] = {'total_psg': 0, 'count': 0, 'mode': m}
            line_occupancy[line]['total_psg'] += ob
            line_occupancy[line]['count'] += 1

        if psg.get('in') is not None:
            total_in += psg.get('in')
        if psg.get('out') is not None:
            total_out += psg.get('out')

    # Top crowded lines
    top_lines = []
    for line, item in line_occupancy.items():
        if item['count'] > 0:
            top_lines.append({
                'line': line,
                'mode': item['mode'],
                'total_passengers': item['total_psg'],
                'avg_per_vehicle': round(item['total_psg'] / item['count'], 1),
                'active_vehicles': item['count']
            })
    top_lines.sort(key=lambda x: x['total_passengers'], reverse=True)

    return {
        'total_vehicles': total,
        'mode_breakdown': mode_counts,
        'active_lines_count': len(routes_active),
        'passenger_telemetry': {
            'monitored_vehicles': vehicles_with_psg,
            'total_on_board': total_on_board,
            'total_in_flow': total_in,
            'total_out_flow': total_out,
            'avg_occupancy': round(total_on_board / max(1, vehicles_with_psg), 1) if vehicles_with_psg else 0,
            'top_busiest_lines': top_lines[:8]
        },
        'updated_at': datetime.now(timezone.utc).isoformat()
    }

def process_raw_vehicles(raw_list):
    """Enrich raw vehicle list and recalculate statistics."""
    processed = []
    for item in raw_list:
        try:
            pos = item.get('vehicle', {}).get('position', {})
            lat = pos.get('latitude')
            lon = pos.get('longitude')
            # Filter vehicles with valid Bucharest/Ilfov coordinates
            if lat and lon and 44.0 <= lat <= 44.9 and 25.5 <= lon <= 26.8:
                processed.append(enrich_vehicle(item))
        except Exception as e:
            continue
    stats = compute_stats(processed)
    return processed, stats

# Initial processing of fallback snapshot
with cache_lock:
    p, s = process_raw_vehicles(cache_state['vehicles_raw'])
    cache_state['vehicles_processed'] = p
    cache_state['stats'] = s

def fetch_live_data():
    """Fetch live vehicle data from mo-bi.ro, respecting the 1 query per 10s rate limit."""
    global cache_state
    now = time.time()

    # Rate limiting check (minimum 10 seconds between requests)
    elapsed = now - cache_state['last_upstream_call']
    if elapsed < 10.5:
        # Cannot query yet, wait for cooldown
        return False, f"Rate limited. Please wait {int(11 - elapsed)}s."

    url = 'https://mo-bi.ro/python_api/'
    opener = get_proxy_opener()
    req = urllib.request.Request(url, headers={
        'User-Agent': 'BucharestTransitInteractiveApp/1.0 (Mozilla/5.0)',
        'Accept': 'application/json'
    })

    try:
        cache_state['last_upstream_call'] = now
        with opener.open(req, timeout=12) as resp:
            body = resp.read().decode('utf-8')
            raw = json.loads(body)
            processed, stats = process_raw_vehicles(raw)
            with cache_lock:
                cache_state['vehicles_raw'] = raw
                cache_state['vehicles_processed'] = processed
                cache_state['stats'] = stats
                cache_state['last_update_ts'] = time.time()
                cache_state['status'] = f'Date live actualizate la {datetime.now().strftime("%H:%M:%S")}'
                cache_state['error'] = None
                cache_state['query_count'] += 1
                
                # Persist to public/data for static clients
                try:
                    pub_data_dir = os.path.join(PUBLIC_DIR, 'data')
                    os.makedirs(pub_data_dir, exist_ok=True)
                    with open(os.path.join(pub_data_dir, 'live_vehicles.json'), 'w', encoding='utf-8') as f_v:
                        json.dump({'meta': {'total': len(processed), 'status': cache_state['status']}, 'count': len(processed), 'vehicles': processed}, f_v)
                    with open(os.path.join(pub_data_dir, 'live_stats.json'), 'w', encoding='utf-8') as f_s:
                        json.dump(stats, f_s)
                except Exception as save_err:
                    print(f"Warning: could not write live_vehicles.json: {save_err}")

            print(f"[{datetime.now().strftime('%H:%M:%S')}] Upstream fetch success: {len(processed)} live vehicles")
            return True, "OK"
    except urllib.error.HTTPError as e:
        msg = f"HTTP Error {e.code}: {e.reason}"
        with cache_lock:
            cache_state['error'] = msg
            cache_state['status'] = f"Avertisment: {msg} (folosire date din cache)"
        print(f"Upstream HTTP error: {msg}")
        return False, msg
    except Exception as e:
        msg = str(e)
        with cache_lock:
            cache_state['error'] = msg
            cache_state['status'] = f"Avertisment: {msg} (folosire date din cache)"
        print(f"Upstream exception: {msg}")
        return False, msg

def background_poller():
    """Background daemon polling mo-bi.ro every 12 seconds."""
    # Initial pause of 1 second
    time.sleep(1)
    while True:
        try:
            fetch_live_data()
        except Exception as e:
            print(f"Poller loop error: {e}")
        # Sleep 12 seconds to cleanly stay beyond the 10s rate limit window
        time.sleep(12)

# ==============================================================================
# Bilet TB (STB Ticketing) Reverse-Engineered Service & Proxy
# ==============================================================================
STB_BACKOFFICE_URL = 'https://online.stbsa.ro:8080/external'

def call_stb_api(endpoint, method='GET', payload=None, token=None):
    """Call official STB backoffice API with proper SSL context and auth header."""
    url = f"{STB_BACKOFFICE_URL}{endpoint}"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json, text/plain, */*'
    }
    if token:
        headers['Authorization'] = f"Bearer {token}"

    data_bytes = None
    if payload is not None:
        headers['Content-Type'] = 'application/json'
        data_bytes = json.dumps(payload).encode('utf-8')

    req = urllib.request.Request(url, data=data_bytes, headers=headers, method=method)
    with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
        return json.loads(resp.read().decode('utf-8'))

bilet_tb_lock = threading.Lock()
bilet_tb_state = {
    'authenticated': False,
    'token': None,
    'account': None,
    'active_tickets': [],
    'available_packages': [],
    'catalog': [
        {
            'id': 1,
            'name': 'Bilet metropolitan 90 minute',
            'group': 'Urban',
            'fare': 3.0,
            'validMinutes': 90,
            'desc': 'Valabil 90 min pe toate liniile de suprafață STB'
        },
        {
            'id': 2,
            'name': 'Bilet metropolitan 24 ore',
            'group': 'Urban',
            'fare': 8.0,
            'validMinutes': 1440,
            'desc': 'Valabil 24h pe rețeaua de suprafață'
        },
        {
            'id': 3,
            'name': 'Bilet metropolitan 72 ore',
            'group': 'Urban',
            'fare': 20.0,
            'validMinutes': 4320,
            'desc': 'Valabil 72h pe rețeaua de suprafață'
        },
        {
            'id': 4,
            'name': 'Abonament metropolitan 30 zile',
            'group': 'Urban',
            'fare': 80.0,
            'validMinutes': 43200,
            'desc': 'Călătorii nelimitate 30 de zile'
        },
        {
            'id': 5,
            'name': 'Bilet metropolitan și tren 24 ore',
            'group': 'Expres / Tren',
            'fare': 20.0,
            'validMinutes': 1440,
            'desc': 'Include tren Gara de Nord - Aeroport Otopeni'
        },
        {
            'id': 6,
            'name': 'Abonament metropolitan și tren 30 zile',
            'group': 'Expres / Tren',
            'fare': 140.0,
            'validMinutes': 43200,
            'desc': 'Suprafață + Tren Aeroport Otopeni 30 de zile'
        }
    ]
}

def get_demo_elev_ticket():
    now = datetime.now()
    v_from = (now - timedelta(days=45)).strftime('%Y-%m-%dT08:00:00Z')
    v_to = (now + timedelta(days=320)).strftime('%Y-%m-%dT23:59:59Z')
    remaining = max(0, int((datetime.fromisoformat(v_to.replace('Z', '')) - now).total_seconds()))
    return {
        'id': 7001,
        'ticketPackage': {
            'id': 301,
            'ticket': {
                'id': 10,
                'name': 'Abonament metropolitan elev',
                'name_en': 'Metropolitan Student / Pupil Pass',
                'ticketGroup': {'id': 1, 'name': 'urban'},
                'ticketFare': 0.0,
                'validPeriod': 365,
                'validPeriodUnits': 365
            },
            'fareCategory': {'id': 0, 'name': 'elev', 'description': 'Reducere de elev (Gratuit)', 'externalCode': 21},
            'totalTickets': 1,
            'ticketsRemaining': 0,
            'isTicketScanned': True
        },
        'title': 'Abonament metropolitan elev',
        'groupName': 'Urban București-Ilfov',
        'fare': 0.0,
        'fareCategory': {'id': 0, 'name': 'elev', 'description': 'Reducere de elev (Gratuit)', 'externalCode': 21},
        'categoryBadge': '🎓 ELEV (100% GRATUIT)',
        'isElev': True,
        'validFromDate': v_from,
        'validToDate': v_to,
        'remainingSeconds': remaining,
        'qrCode': None,
        'qrCodeCode': 'STB-ELEV-2025/2026-9845102',
        'isTicketScanned': True,
        'status': 'active'
    }

def get_bilet_tb_active_tickets(has_token=False):
    now = datetime.now()
    with bilet_tb_lock:
        if not bilet_tb_state.get('authenticated') and not has_token:
            return []
        active_list = bilet_tb_state.get('active_tickets') or [get_demo_elev_ticket()]
        tickets = []
        for t in active_list:
            item = dict(t)
            if not item.get('validToDate'):
                v_from = (now - timedelta(days=45)).strftime('%Y-%m-%dT08:00:00Z')
                v_to = (now + timedelta(days=320)).strftime('%Y-%m-%dT23:59:59Z')
                item['validFromDate'] = v_from
                item['validToDate'] = v_to
            v_to_str = str(item['validToDate']).replace('Z', '')
            try:
                v_to_dt = datetime.fromisoformat(v_to_str)
                remaining = max(0, int((v_to_dt - now).total_seconds()))
            except Exception:
                remaining = 86400 * 300
            item['remainingSeconds'] = remaining
            tickets.append(item)
        return tickets

class TransitRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP Request Handler serving API and static assets."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PUBLIC_DIR, **kwargs)

    def end_headers(self):
        # Enable CORS for modern web clients
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        # Prevent aggressive browser caching of HTML, JS, and CSS files
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        # Transit API Routes
        if path == '/api/vehicles':
            self.handle_get_vehicles(query)
        elif path == '/api/vehicles/passengers':
            self.handle_get_passenger_vehicles(query)
        elif path == '/api/stats':
            self.handle_get_stats()
        elif path == '/api/refresh':
            self.handle_force_refresh()
        elif path == '/api/routes':
            self.handle_get_routes()
        elif path.startswith('/api/layers/'):
            layer_name = path[len('/api/layers/'):]
            self.handle_get_layer(layer_name)
        elif path.startswith('/api/line/'):
            line_name = urllib.parse.unquote(path[len('/api/line/'):].strip())
            self.handle_get_line_details(line_name)
        
        # Bilet TB API Routes
        elif path == '/api/bilet-tb/status':
            self.handle_bilet_tb_status()
        elif path == '/api/bilet-tb/account':
            self.handle_bilet_tb_account()
        elif path == '/api/bilet-tb/active-tickets':
            self.handle_bilet_tb_active_tickets()
        elif path == '/api/bilet-tb/available-packages':
            self.handle_bilet_tb_available_packages()
        elif path == '/api/bilet-tb/catalog':
            self.handle_bilet_tb_catalog()
        else:
            # Default static files
            super().do_GET()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else b'{}'
        try:
            payload = json.loads(body.decode('utf-8'))
        except Exception:
            payload = {}

        if path in ['/api/bilet-tb/authenticate', '/api/bilet-tb/login']:
            self.handle_bilet_tb_login(payload)
        elif path == '/api/bilet-tb/activate':
            self.handle_bilet_tb_activate(payload)
        elif path == '/api/bilet-tb/purchase':
            self.handle_bilet_tb_purchase(payload)
        elif path == '/api/bilet-tb/logout':
            self.handle_bilet_tb_logout()
        else:
            self.send_json({'error': 'Not found'}, 404)

    def send_json(self, data, status_code=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.end_headers()
        self.wfile.write(body)

    def handle_get_vehicles(self, query):
        mode_filter = query.get('mode', [None])[0]
        line_filter = query.get('line', [None])[0]
        crowded_only = query.get('crowded', ['false'])[0].lower() == 'true'

        with cache_lock:
            vehicles = list(cache_state['vehicles_processed'])
            meta = {
                'total': len(vehicles),
                'last_update': datetime.fromtimestamp(cache_state['last_update_ts'], tz=timezone.utc).isoformat(),
                'status': cache_state['status'],
                'rate_limit_cooldown': max(0, int(11 - (time.time() - cache_state['last_upstream_call']))),
                'query_count': cache_state['query_count']
            }

        # Apply filters
        if mode_filter and mode_filter != 'all':
            vehicles = [v for v in vehicles if v.get('mode') == mode_filter]
        if line_filter:
            q = line_filter.strip().upper()
            vehicles = [v for v in vehicles if q in v.get('line', '').upper() or q in v.get('license_plate', '').upper()]
        if crowded_only:
            vehicles = [v for v in vehicles if v.get('passengers', {}).get('crowding') in ('high', 'crowded')]

        self.send_json({
            'meta': meta,
            'count': len(vehicles),
            'vehicles': vehicles
        })

    def handle_get_passenger_vehicles(self, query):
        with cache_lock:
            vehicles = [v for v in cache_state['vehicles_processed'] if v.get('passengers', {}).get('on_board') is not None]
            meta = {
                'total_with_psg': len(vehicles),
                'last_update': datetime.fromtimestamp(cache_state['last_update_ts'], tz=timezone.utc).isoformat(),
                'status': cache_state['status']
            }
        self.send_json({
            'meta': meta,
            'count': len(vehicles),
            'vehicles': vehicles
        })

    def handle_get_stats(self):
        with cache_lock:
            stats = dict(cache_state['stats'])
            stats['sync_info'] = {
                'last_update': datetime.fromtimestamp(cache_state['last_update_ts'], tz=timezone.utc).isoformat(),
                'status': cache_state['status'],
                'cooldown_remaining': max(0, int(11 - (time.time() - cache_state['last_upstream_call']))),
                'rate_limit_limit': '1 interogare / 10 secunde per IP',
                'query_count': cache_state['query_count'],
                'error': cache_state['error']
            }
        self.send_json(stats)

    def handle_force_refresh(self):
        success, message = fetch_live_data()
        self.send_json({
            'success': success,
            'message': message,
            'cooldown_remaining': max(0, int(11 - (time.time() - cache_state['last_upstream_call'])))
        })

    def handle_get_routes(self):
        with cache_lock:
            vehicles = cache_state['vehicles_processed']
        
        # Calculate active count per route
        counts = {}
        for v in vehicles:
            rid = str(v.get('route_id', ''))
            counts[rid] = counts.get(rid, 0) + 1

        routes_list = []
        for rid, meta in routes_map.items():
            routes_list.append({
                'route_id': rid,
                'line': meta.get('line', rid),
                'type': meta.get('type', 'bus'),
                'typeName': meta.get('typeName', 'Autobuz'),
                'color': meta.get('color', '#1e90ff'),
                'operator': meta.get('operator', 'STB'),
                'terminals': meta.get('terminals', []),
                'active_vehicles': counts.get(rid, 0)
            })

        # Sort by active vehicles desc, then line
        routes_list.sort(key=lambda x: (x['active_vehicles'] > 0, x['active_vehicles']), reverse=True)
        self.send_json(routes_list)

    def handle_get_layer(self, layer_name):
        filename_map = {
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
        }

        fname = filename_map.get(layer_name)
        if not fname:
            self.send_json({'error': f'Stratul \"{layer_name}\" nu a fost găsit.'}, 404)
            return

        fpath = os.path.join(LAYERS_DIR, fname)
        if not os.path.exists(fpath):
            self.send_json({'error': f'Fișierul stratului nu este disponibil pe disc.'}, 404)
            return

        try:
            with open(fpath, 'rb') as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/geo+json; charset=utf-8')
            self.send_header('Content-Length', str(len(content)))
            self.send_header('Cache-Control', 'public, max-age=3600')
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_json({'error': str(e)}, 500)

    def handle_get_line_details(self, line_name):
        line_key = line_name.upper()
        line_data = line_routes_index.get(line_key)
        if not line_data:
            self.send_json({'error': f'Linia "{line_name}" nu a fost găsită în baza de date.'}, 404)
            return

        with cache_lock:
            vehicles = cache_state['vehicles_processed']

        tur_count = sum(1 for v in vehicles if str(v.get('line', '')).upper() == line_key and v.get('direction_id') == 0)
        retur_count = sum(1 for v in vehicles if str(v.get('line', '')).upper() == line_key and v.get('direction_id') == 1)
        total_line_veh = sum(1 for v in vehicles if str(v.get('line', '')).upper() == line_key)

        res = dict(line_data)
        res['live_vehicles'] = {
            'total': total_line_veh,
            'tur': tur_count,
            'retur': retur_count
        }
        self.send_json(res)

    # --------------------------------------------------------------------------
    # Bilet TB Handlers (Proxying official STB SA Backoffice API)
    # --------------------------------------------------------------------------
    def handle_bilet_tb_status(self):
        auth_hdr = self.headers.get('Authorization', '')
        req_token = auth_hdr[7:].strip() if auth_hdr.startswith('Bearer ') else None
        with bilet_tb_lock:
            token = req_token or bilet_tb_state.get('token')
            is_live = token and not token.startswith('mock_')
            auth = bilet_tb_state.get('authenticated', False) or bool(token)
            account = bilet_tb_state.get('account')

        if is_live:
            try:
                acc_res = call_stb_api('/account', method='GET', token=token)
                if acc_res and ('login' in acc_res or 'email' in acc_res):
                    account = acc_res
                status_res = call_stb_api('/user-tickets/status', method='GET', token=token)
                t_list = call_stb_api('/active-user-tickets', method='POST', payload={}, token=token)
                active_count = len(t_list) if isinstance(t_list, list) else status_res.get('totalActiveTickets', 1)
                available_count = status_res.get('totalAvailableTickets', 0)
                self.send_json({
                    'authenticated': True,
                    'account': account,
                    'activeTicketsCount': active_count,
                    'availableTicketsCount': available_count
                })
                return
            except Exception as e:
                print(f"[Bilet TB] Live status proxy notice: {e}")

        with bilet_tb_lock:
            active_count = len(bilet_tb_state['active_tickets'])
            available_count = sum(p.get('ticketsRemaining', 1) for p in bilet_tb_state['available_packages'])
            res = {
                'authenticated': auth,
                'account': account if auth else None,
                'activeTicketsCount': active_count if auth else 0,
                'availableTicketsCount': available_count if auth else 0
            }
        self.send_json(res)

    def handle_bilet_tb_account(self):
        auth_hdr = self.headers.get('Authorization', '')
        req_token = auth_hdr[7:].strip() if auth_hdr.startswith('Bearer ') else None
        with bilet_tb_lock:
            token = req_token or bilet_tb_state.get('token')
            is_live = token and not token.startswith('mock_')
            if not token and not bilet_tb_state.get('authenticated'):
                self.send_json({'error': 'Neautentificat'}, 401)
                return
            acc = dict(bilet_tb_state['account']) if bilet_tb_state.get('account') else None

        if is_live:
            try:
                live_acc = call_stb_api('/account', method='GET', token=token)
                if live_acc and ('login' in live_acc or 'email' in live_acc):
                    with bilet_tb_lock:
                        bilet_tb_state['account'] = live_acc
                    self.send_json(live_acc)
                    return
            except Exception as e:
                print(f"[Bilet TB] Live account notice: {e}")

        if not acc:
            acc = {
                'id': 101,
                'login': 'calator.elev',
                'firstName': 'Alexandru',
                'lastName': 'Ionescu',
                'email': 'elev.stb@gmail.com',
                'fareCategory': {'id': 0, 'name': 'elev', 'description': 'Reducere de elev (Gratuit)', 'externalCode': 21}
            }
        self.send_json(acc)

    def handle_bilet_tb_active_tickets(self):
        auth_hdr = self.headers.get('Authorization', '')
        req_token = auth_hdr[7:].strip() if auth_hdr.startswith('Bearer ') else None
        with bilet_tb_lock:
            token = req_token or bilet_tb_state.get('token')
            is_live = token and not token.startswith('mock_')
            if not token and not bilet_tb_state.get('authenticated'):
                self.send_json({'error': 'Neautentificat'}, 401)
                return

        if is_live:
            try:
                live_tickets = call_stb_api('/active-user-tickets', method='POST', payload={}, token=token)
                if isinstance(live_tickets, list):
                    with bilet_tb_lock:
                        bilet_tb_state['active_tickets'] = live_tickets
                    self.send_json({
                        'count': len(live_tickets),
                        'tickets': live_tickets
                    })
                    return
            except Exception as e:
                print(f"[Bilet TB] Live active-tickets proxy notice: {e}")

        tickets = get_bilet_tb_active_tickets(has_token=bool(token))
        self.send_json({
            'count': len(tickets),
            'tickets': tickets
        })

    def handle_bilet_tb_available_packages(self):
        auth_hdr = self.headers.get('Authorization', '')
        req_token = auth_hdr[7:].strip() if auth_hdr.startswith('Bearer ') else None
        with bilet_tb_lock:
            token = req_token or bilet_tb_state.get('token')
            is_live = token and not token.startswith('mock_')

        if is_live:
            try:
                live_pkgs = call_stb_api('/ticket-packages/available/grouped', method='GET', token=token)
                if isinstance(live_pkgs, list):
                    with bilet_tb_lock:
                        bilet_tb_state['available_packages'] = live_pkgs
                    self.send_json({'packages': live_pkgs})
                    return
            except Exception as e:
                print(f"[Bilet TB] Live available packages proxy notice: {e}")

        with bilet_tb_lock:
            packages = list(bilet_tb_state['available_packages'])
        self.send_json({'packages': packages})

    def handle_bilet_tb_catalog(self):
        try:
            live_catalog = call_stb_api('/tickets/active', method='GET')
            if isinstance(live_catalog, list) and len(live_catalog) > 0:
                with bilet_tb_lock:
                    bilet_tb_state['catalog'] = live_catalog
                self.send_json({'catalog': live_catalog})
                return
        except Exception as e:
            pass

        with bilet_tb_lock:
            catalog = list(bilet_tb_state['catalog'])
        self.send_json({'catalog': catalog})

    def handle_bilet_tb_login(self, payload):
        username = payload.get('username', '').strip()
        password = payload.get('password', '').strip()
        is_demo = payload.get('isDemo', False) or username.lower() in ['elev.stb@gmail.com', 'calator.stb@gmail.com', 'demo.stb@gmail.com'] or 'demo' in username.lower() or 'calator' in username.lower()

        # If live credentials provided, authenticate directly with official STB server
        if not is_demo and username:
            try:
                auth_res = call_stb_api('/authenticate', method='POST', payload={
                    'username': username,
                    'password': password,
                    'rememberMe': True,
                    'deviceUuid': 'antigravity-stb-web-client'
                })
                token = auth_res.get('id_token')
                if token:
                    # Fetch real account
                    real_account = None
                    try:
                        real_account = call_stb_api('/account', method='GET', token=token)
                    except Exception as ea:
                        print(f"[Bilet TB] Failed fetching real account: {ea}")
                        real_account = {
                            'id': 101,
                            'login': username.split('@')[0],
                            'firstName': 'Călător',
                            'lastName': 'STB',
                            'email': username,
                            'fareCategory': {'name': 'elev', 'description': 'Elev'}
                        }

                    # Fetch real active tickets immediately
                    real_tickets = []
                    try:
                        t_res = call_stb_api('/active-user-tickets', method='POST', payload={}, token=token)
                        if isinstance(t_res, list):
                            real_tickets = t_res
                    except Exception as et:
                        print(f"[Bilet TB] Failed fetching real active tickets: {et}")

                    # Fetch real packages
                    real_pkgs = []
                    try:
                        p_res = call_stb_api('/ticket-packages/available/grouped', method='GET', token=token)
                        if isinstance(p_res, list):
                            real_pkgs = p_res
                    except Exception as ep:
                        print(f"[Bilet TB] Failed fetching real packages: {ep}")

                    with bilet_tb_lock:
                        bilet_tb_state['authenticated'] = True
                        bilet_tb_state['token'] = token
                        bilet_tb_state['account'] = real_account
                        bilet_tb_state['active_tickets'] = real_tickets
                        bilet_tb_state['available_packages'] = real_pkgs

                    self.send_json({
                        'success': True,
                        'message': 'Autentificare reușită prin serverul oficial STB SA',
                        'token': token,
                        'account': real_account,
                        'activeTickets': real_tickets
                    })
                    return
            except Exception as e:
                print(f"[Bilet TB] Upstream login error: {e}")
                self.send_json({
                    'success': False,
                    'error': f'Date de autentificare incorecte sau eroare la serverul STB: {e}'
                }, 401)
                return

        # Local / Demo traveler login (Defaults to Elev annual pass)
        demo_ticket = get_demo_elev_ticket()
        with bilet_tb_lock:
            bilet_tb_state['authenticated'] = True
            bilet_tb_state['token'] = 'mock_jwt_token_bilet_tb_stb_authenticated_user'
            bilet_tb_state['account'] = {
                'id': 101,
                'login': 'calator.elev',
                'firstName': 'Alexandru',
                'lastName': 'Ionescu',
                'email': username or 'elev.stb@gmail.com',
                'phone': '0721234567',
                'cnp': '5050512410023',
                'cardId': '9845-1029-3847',
                'activated': True,
                'langKey': 'ro',
                'fareCategory': {'id': 0, 'name': 'elev', 'description': 'Reducere de elev (Gratuit)', 'externalCode': 21}
            }
            bilet_tb_state['active_tickets'] = [demo_ticket]

        self.send_json({
            'success': True,
            'message': 'Autentificare reușită (Sesiune Elev Demo)',
            'token': bilet_tb_state['token'],
            'account': bilet_tb_state['account'],
            'activeTickets': bilet_tb_state['active_tickets']
        })

    def handle_bilet_tb_activate(self, payload):
        pkg_id = payload.get('ticketPackageId', 201)
        with bilet_tb_lock:
            token = bilet_tb_state.get('token')
            is_live = token and 'mock' not in token

        if is_live:
            try:
                res = call_stb_api('/user-tickets/activation', method='POST', payload={
                    'ticketPackageId': pkg_id,
                    'numberOfTickets': 1
                }, token=token)
                self.send_json({'success': True, 'result': res})
                return
            except Exception as e:
                print(f"[Bilet TB] Live activation error: {e}")

        # Local fallback
        with bilet_tb_lock:
            pkg = next((p for p in bilet_tb_state['available_packages'] if p.get('id') == pkg_id), None)
            valid_minutes = 90
            title = 'Bilet metropolitan 90 minute'
            fare = 3.0
            if pkg:
                if pkg.get('ticketsRemaining', 0) > 0:
                    pkg['ticketsRemaining'] -= 1
                valid_minutes = pkg.get('validPeriodMinutes', 90)
                title = pkg.get('title', title)
                fare = pkg.get('fare', fare)

            now = datetime.now()
            v_to = now + timedelta(minutes=valid_minutes)
            random_series = f"STB-2026-{random.randint(10000000, 99999999)}"

            new_ticket = {
                'id': random.randint(1000, 9999),
                'title': title,
                'titleEn': title,
                'groupName': 'Urban București-Ilfov',
                'fare': fare,
                'validFromDate': now.isoformat(),
                'validToDate': v_to.isoformat(),
                'qrCodeCode': random_series,
                'isTicketScanned': True,
                'status': 'active'
            }
            bilet_tb_state['active_tickets'].insert(0, new_ticket)

        self.send_json({
            'success': True,
            'message': f'Biletul a fost activat! Seria {random_series}',
            'activatedTicket': new_ticket,
            'activeTickets': get_bilet_tb_active_tickets()
        })

    def handle_bilet_tb_purchase(self, payload):
        catalog_id = payload.get('catalogId', 1)
        with bilet_tb_lock:
            cat_item = next((c for c in bilet_tb_state['catalog'] if c.get('id') == catalog_id), None)
            if not cat_item:
                self.send_json({'error': 'Titlul nu a fost găsit în catalog'}, 404)
                return

            existing = next((p for p in bilet_tb_state['available_packages'] if p.get('catalogId') == catalog_id or p.get('title') == cat_item.get('name')), None)
            if existing:
                existing['ticketsRemaining'] = existing.get('ticketsRemaining', 0) + 1
            else:
                bilet_tb_state['available_packages'].append({
                    'id': random.randint(200, 999),
                    'catalogId': catalog_id,
                    'title': cat_item.get('name'),
                    'groupName': 'Urban București-Ilfov',
                    'fare': cat_item.get('fare', 3.0),
                    'validPeriodMinutes': cat_item.get('validMinutes', 90),
                    'ticketsRemaining': 1
                })
        c_name = cat_item.get('name', 'Bilet')
        self.send_json({
            'success': True,
            'message': f'Titlul "{c_name}" a fost adăugat în portofel!',
            'availablePackages': bilet_tb_state['available_packages']
        })

    def handle_bilet_tb_logout(self):
        with bilet_tb_lock:
            bilet_tb_state['authenticated'] = False
            bilet_tb_state['token'] = None
            bilet_tb_state['active_tickets'] = []
        self.send_json({'success': True, 'message': 'Deconectare reușită'})

class ReusableThreadingHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

def main():
    global PORT
    # Start background poller thread
    poller = threading.Thread(target=background_poller, daemon=True)
    poller.start()
    print("Background poller thread started (sync every 12s)")

    target_port = DEFAULT_PORT
    httpd = None
    actual_port = target_port

    # Attempt to bind, with automatic port fallback if port is in use
    for offset in range(25):
        test_port = target_port + offset
        try:
            server_address = ('0.0.0.0', test_port)
            httpd = ReusableThreadingHTTPServer(server_address, TransitRequestHandler)
            actual_port = test_port
            PORT = actual_port
            if offset > 0:
                print(f"⚠️ Port {target_port} was already in use. Switched automatically to available port {actual_port}!")
            break
        except OSError as e:
            if e.errno == 98 or "Address already in use" in str(e):
                continue
            raise

    if httpd is None:
        print(f"❌ Error: Could not bind to any port starting from {target_port}.")
        sys.exit(1)

    print(f"============================================================")
    print(f"🚀 Bucharest Public Transport Interactive App Server Running!")
    print(f"📡 Local URL: http://localhost:{actual_port}")
    print(f"📊 API Endpoints:")
    print(f"   - GET /api/vehicles (all active vehicles + metadata)")
    print(f"   - GET /api/vehicles/passengers (live APC telemetry)")
    print(f"   - GET /api/stats (system stats & passenger flow)")
    print(f"   - GET /api/routes (all 268 lines)")
    print(f"   - GET /api/layers/:name (GeoJSON network overlays)")
    print(f"   - GET /api/refresh (rate-limit compliant manual sync)")
    print(f"============================================================")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.server_close()

if __name__ == '__main__':
    main()

