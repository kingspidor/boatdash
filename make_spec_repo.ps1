param(
  [string]$RepoName = "boatdash-spec",
  [string]$Owner    = "kingspidor",
  [ValidateSet('public','private')] [string]$Visibility = 'public',
  [switch]$OpenWeb
)
$ErrorActionPreference = 'Stop'

function New-Dir([string]$p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

# Create repo folder in current directory
$root = Join-Path (Get-Location) $RepoName
New-Dir $root
Set-Location $root

# Basic hygiene files
@"*
text=auto eol=lf
"@ | Set-Content .gitattributes -Encoding ascii

@"# Build artifacts
build/
*.bin
*.elf
*.map
.DS_Store
Thumbs.db
"@ | Set-Content .gitignore -Encoding ascii

$year=(Get-Date).Year
@"MIT License

Copyright (c) $year $Owner

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@ | Set-Content LICENSE -Encoding ascii

# Write the SPEC from canvas into README.md
@'
#  SPEC-1-ESP32S3 SoftAP + OTA (Async)

## Background

An ESP32‑S3‑DevKitC‑1 (N16R8) will be installed in a **boat dashboard**. It serves a **self‑hosted web UI** over its own **SoftAP** showing **ADC‑based gauges** (e.g., battery voltage, fuel level, temp, oil pressure). A technician (phone/laptop) connects directly to the device to view gauges and perform **OTA firmware updates**. Internet access is not guaranteed.

**Updated assumptions (validate):**

- SoftAP is **always‑on** (not only for provisioning) and the primary way users connect.
- OTA is **web‑based** (upload a .bin via browser) with authentication and safe‑rollback.
- ADC readings need to be **smooth, calibrated, and responsive** while networking runs **asynchronously**.
- Marine environment ⇒ intermittent power; we should be resilient to brownouts and incomplete updates.
- Mobile‑first UI (phones/tablets on deck), works offline.



## Requirements

**MoSCoW Prioritization**

**Must Have**

- **Platform**: Arduino IDE build targeting **ESP32‑S3‑DevKitC‑1 (N16R8)**; non‑blocking architecture (no long `delay()`), watchdog enabled.
- **Networking**: SoftAP **always‑on** with WPA2‑PSK; SSID format `BOATDASH-<last4MAC>`; configurable PSK; AP IP e.g. `192.168.4.1`.
- **Web UI**: Mobile‑friendly dashboard rendering **ADC gauges**; live updates ≥ **5 fps**; no page reloads.
- **Sampling/Filters**: ADC1 channels only for Wi‑Fi coexistence; sampling ≥ **100 Hz** per channel; moving average + low‑pass (IIR) filtering; per‑channel scaling & calibration.
- **Signals**: **Tach via optocoupler** → PCNT; Analog: **Battery Voltage (divider)**, **Fuel Level (sender)**, **Temperature x3 (TMP36)**.
- **OTA**: Browser‑based firmware upload endpoint with auth; stream to flash without buffering whole file; **dual‑OTA partition** layout with automatic **rollback** on boot‑fail; preserve settings.
- **Storage**: NVS for calibration & settings (channel names, scale, offsets, smoothing); transactional writes and versioning.
- **Security**: Auth required for settings and OTA; rate‑limit login; optional AP isolation; no open endpoints.
- **Resilience**: Power‑loss safe OTA (bootloader/rollback); brownout detector enabled; safe writes to NVS; clear recovery path to known‑good firmware.
- **Diagnostics**: Status page with device info, firmware version, uptime, Wi‑Fi RSSI, free heap/PSRAM; download of recent logs.

**Should Have**

- **AP+STA** concurrent mode (joins marina Wi‑Fi if configured) while keeping SoftAP available; STA is optional.
- **Captive portal** for easier discovery (redirect to dashboard on connect).
- **Static assets** served from **LittleFS** with gzip; WebSocket/SSE for real‑time gauge updates.
- **Timekeeping** via RTC/monotonic timers; NTP when STA or cellular is connected.
- **Relay controls** (UI + GPIO) for **Nav Lights**, **All‑Around Light**, **Spotlight** with safe defaults and state feedback.

**Could Have**

- **HTTPS** on AP with self‑signed cert (if performance/flash allows), or at minimum digest auth for OTA.

- **Cal/Profiles**: Multiple calibration profiles; import/export JSON config.

- **Logging**: Ring buffer persisted on request; downloadable diagnostics bundle.

- **Visuals**: Dark/bright themes; haptics/beeps (if hardware) on alerts.

- **HTTPS** on AP with self‑signed cert (if performance/flash allows), or at minimum digest auth for OTA.

- **Cal/Profiles**: Multiple calibration profiles; import/export JSON config.

- **Logging**: Ring buffer persisted on request; downloadable diagnostics bundle.

- **Visuals**: Dark/bright themes; haptics/beeps (if hardware) on alerts.

**Won’t Have (MVP)**

- Dedicated **cellular modem backhaul** (no BG95/SIM7xxx/SIM7600 hardware).
- Cloud connectivity beyond basic local telemetry; NMEA 2000/CAN integrations, GPS onboard receivers.
- Remote OTA via internet; OTA remains **local web upload over SoftAP**.



## Method

### Overview (ESP-IDF 5.4)

- **Base**: **ESP-IDF 5.4** (no Arduino). Event‑driven, non‑blocking tasks.
- **Networking**: `esp_wifi` in **AP+STA** (AP always‑on, STA optional for hotspot).
- **Web**: `esp_http_server` with **WebSocket** support for live gauges; **asynchronous handlers** for long work; built‑in **captive portal** pattern.
- **OTA**: Browser file‑upload → `esp_ota_begin/write/end`; **bootloader rollback** enabled; call `esp_ota_mark_app_valid_cancel_rollback()` after healthy boot.
- **Storage**: NVS for settings + calibration; `LittleFS/littlefs` (LittleFS via component) for static assets if needed.
- **Peripherals**: `adc_oneshot` driver on **ADC1** channels; **PCNT** (pulse counter) for tach; GPIO outputs for relays.
- **Time**: SNTP when STA/hotspot up; RTC monotonic fallback.
- **BLE (optional)**: NimBLE for BLE‑UART GPS/time bridge.

### Hardware Signal Mapping (proposed)

- **Supply**: Boat 12 V → DC‑DC → **3.3 V** rail. Add LC filter, local decoupling (≥100 µF bulk + 0.1 µF per pin), TVS at 12 V input. Common ground reference.
- **Tach input**: Ignition pulse → **optocoupler** → Schmitt trigger/RC clean‑up → ESP32‑S3 GPIO (PCNT input). **PPR configurable** (default **6/rev** for this build). 3.3 V‑logic only.
- **Analog (ADC1 only)**:
  - **Battery Voltage**: Divider targeting ≤3.3 V at 15 V max (e.g., **R1=12 kΩ**, **R2=3.6 kΩ**, Thevenin ≈2.8 kΩ). Add RC 1 kΩ + 0.1 µF to smooth.
  - **Fuel Level**: Sender → shunt → 0–3.3 V; map via piecewise linear curve.
  - **Temperature x3 (TMP36)**: Powered at **3.3 V**, 0.1 µF per sensor near Vout; short, shielded leads if possible.
- **Relays / Drivers**: 3 outputs for **NAV**, **ALLAROUND**, **SPOTLIGHT** → drive external **12 V automotive relays** (or solid‑state high‑side drivers). Use **ULN2003A** or logic‑level MOSFETs with flyback protection. Default **OFF** on boot.
- **Pins (to confirm)**: `TACH_IN: GPIOx (PCNT)`, `BAT_V: ADC1_CH0`, `FUEL: ADC1_CH1`, `TEMP1: ADC1_CH2`, `TEMP2: ADC1_CH3`, `TEMP3: ADC1_CH4`, `RELAY_NAV: GPIOy`, `RELAY_ALL: GPIOz`, `RELAY_SPOT: GPIOw`.
- **Cellular (optional)**: UART to modem (BG95/SIM7600/SIM7080), 3.8–4.2 V supply for modem, level‑compat via 3.3 V UART, SIM holder, diversity antennas.

### Partitions (16 MB Flash, dual OTA)

Place a `partitions.csv` next to the sketch and select **"Custom"** in Arduino IDE:

```
# Name,   Type, SubType, Offset,  Size,  Flags
nvs,      data, nvs,      ,       64K
nvs_keys, data, nvs_keys, ,        4K
otadata,  data, ota,      ,        8K
phy_init, data, phy,      ,        4K
ota_0,    app,  ota_0,    ,        6M
ota_1,    app,  ota_1,    ,        6M
littlefs, data, LittleFS,   ,        2M
```

This yields **two 6 MB app slots** + **2 MB LittleFS**.

### Tachometer (RPM) algorithm

- **Capture**: Use **PCNT** to count pulses on `TACH_IN` with **glitch filter \~50 µs** to ignore noise.
- **Windowing**: Every **200 ms**, read count Δ and compute RPM: `rpm = (Δ / PPR) * (60 / 0.2)`.
- **Smoothing**: Apply EMA (α=0.2) for display; also detect **engine‑off** if `Δ=0` for >2 s.
- **Limits**: Clamp to configured min/max; raise warning if over‑rev.
- **Fallback**: If PPR low at idle, optionally RMT/period‑measure for finer low‑RPM resolution.

```plantuml
@startuml
skinparam monochrome true
actor User
rectangle ESP32S3 {
  [PCNT Tach] --> (RPM Calc)
  (RPM Calc) --> (EMA Filter)
  [ADC Sampler] --> (Calibrate+Scale)
  (Calibrate+Scale) --> (Gauge Data JSON)
  (EMA Filter) --> (Gauge Data JSON)
  (Gauge Data JSON) --> [Async Web Server]
  [Async Web Server] --> User : WS/SSE frames
}
@enduml
```

### ADC Gauges pipeline

- **Sampling**: Task runs at **100 Hz per channel** on **ADC1** with 11 dB attenuation. Average **8 samples**/reading.
- **Calibration**: Per‑channel `(gain, offset)`; TMP36 supports **2‑point** (ice bath / ambient) optional; fuel sender uses **piecewise linear** map.
- **Conversions**:
  - **Battery V**: `Vbatt = Vadc * ((R1+R2)/R2)` with per‑unit calibration.
  - **TMP36 (°F)**: `T(°F) = ((Vout[V] − 0.5) × 100) × 9/5 + 32` (or with `analogReadMilliVolts()` → mV).
- **Filtering**: Moving average (N=8) + EMA (α=0.2). Output to UI at **5–10 Hz**.
- **No‑Signal detection**: Hardware aid (**\~100 kΩ pull‑down** on each ADC) + firmware thresholds **<50 mV or >3.2 V** (or flatline variance <1 LSB for 2 s) ⇒ flag **NO_SIGNAL**; UI shows strikethrough/gray gauge.
- **Noise controls**: Source impedance ≲3 kΩ to ADC; RC anti‑alias; prefer buffered senders where long harnesses.

### Web/UI & API

- **Transport**: **WebSocket** (or SSE) channel `/stream` broadcasting compact JSON (e.g., `{rpm, battV, fuel, temp1, temp2, temp3, relays:{nav, all, spot}, flags:{chX:valid}}`) at 5–10 Hz.
- **Routes**:
  - `GET /` dashboard (mobile‑first PWA, offline cached).
  - `GET /status` device info.
  - `GET /metrics` Prometheus‑style.
  - `POST /api/settings` (auth) for calibration, AP PSK, PPR, etc.
  - `POST /api/relays` (auth) body `{nav:bool, all:bool, spot:bool}`; responds with current state.
  - `POST /ota` (auth, chunked upload to `Update`).
- **Static**: HTML/JS/CSS from LittleFS with gzip.
- **Captive portal**: Optional `DNSServer` forces first‑hit redirect to `/` when on SoftAP.

### OTA flow (browser upload)

1. Auth → POST firmware `.bin` to `/ota` (no full‑file buffering; stream to `Update`)
2. Verify checksum/size → mark next OTA slot → reboot
3. **Rollback** if boot‑OK flag not set within grace period.



### Component/Module Architecture (ESP‑IDF components)

**Goal:** isolate concerns so each system is swappable and testable. All modules talk via a tiny **message bus** (ESP‑IDF `esp_event`) and/or **queues**. The web server only formats data; sensing/control stays independent.

```
/components
  net_apsta/       # Wi‑Fi AP+STA init, captive‑portal DNS pattern, SNTP state
  http_ui/         # esp_http_server + WebSocket, static files, REST
  ota_fw/          # esp_ota_* upload stream + rollback
  sensors_adc/     # ADC1 channels, calibration, filters, NO_SIGNAL detect
  tach_pcnt/       # PCNT capture, RPM calc (cfg PPR), engine‑off detect
  relays_io/       # GPIO drivers for NAV/ALL/SPOT, safe boot defaults
  config_store/    # NVS schema + migration/versioning, JSON import/export
  msg_bus/         # esp_event event base + helper API (publish/subscribe)
  ui_assets/       # LittleFS/SPIFS image builder for /index.html, /lib/*
/main
  app_main.c       # wires modules, sets timers, heartbeat, watchdog
/LittleFS or /littlefs
  index.html, lib/canvas-gauges.min.js, ...
```

**Event model (esp_event)**

- Base: `APP_EVENTS`.
- IDs: `EV_SENSORS_10HZ`, `EV_RPM_5HZ`, `EV_RELAYS_CHANGED`, `EV_NET_STATUS`, `EV_OTA_PROGRESS`, `EV_CFG_CHANGED`.
- Payloads: small structs passed by pointer; WebSocket frames are built from the latest **snapshot**, not from interrupt context.

**Shared data structs (snapshots)**

```c
// sensors_adc/include/sensors_adc.h
typedef struct {
  float batt_v; float fuel_pct; float temp_b1, temp_b2, temp_b3;  
  bool  v_ok, fuel_ok, b1_ok, b2_ok, b3_ok;                       
} sensors_snapshot_t;

// tach_pcnt/include/tach_pcnt.h
typedef struct { float rpm; bool engine_on; } rpm_snapshot_t;

// relays_io/include/relays_io.h
typedef struct { bool nav, all, spot; } relays_state_t;
```

**WebSocket frame (every 100–200 ms)**

```json
{"rpm": 1240, "battV": 12.7, "fuel": 42.1,
 "tempB1": 68.2, "tempB2": 64.5, "tempB3": 70.3,
 "relays": {"nav":false, "all":false, "spot":true},
 "flags": {"battV": true, "fuel": true, "tempB1": true, "tempB2": false, "tempB3": true},
 "net": {"ap": true, "sta": true, "ntp": true}}
```

**REST endpoints**

- `POST /api/relays` → body `{nav?:bool, all?:bool, spot?:bool}` → returns `relays_state_t`.
- `POST /api/settings` → JSON with calibration, PPR, thresholds (`warnTemp`, `overTemp`), SSIDs.
- `POST /ota` → raw body stream; emits `EV_OTA_PROGRESS`.
- `GET /status` → device info / heap / RSSI / versions.

**Partition notes (IDF)**

- Use an IDF `partitions.csv` (dual‑OTA + FS). The earlier Arduino wording can be ignored now; we will ship an IDF‑style CSV with `ota_0`, `ota_1`, and `littlefs`/`LittleFS`.

```plantuml
@startuml
skinparam monochrome true
package "ESP32‑S3 (IDF)" {
  [sensors_adc] --> (msg_bus)
  [tach_pcnt] --> (msg_bus)
  [relays_io] --> (msg_bus)
  (msg_bus) --> [http_ui]
  [config_store] --> [sensors_adc]
  [config_store] --> [tach_pcnt]
  [config_store] --> [relays_io]
  [http_ui] --> [ota_fw]
  [net_apsta] --> (msg_bus)
  [http_ui] --> User : WS/REST
}
@enduml
```

---

## Implementation

### Partitions (16 MB flash)

Create `partitions.csv` in the project root and set it in `menuconfig → Partition Table`:

```
# Name,   Type, SubType, Offset,  Size,  Flags
nvs,      data, nvs,      ,       64K
otadata,  data, ota,      ,        8K
phy_init, data, phy,      ,        4K
factory,  app,  factory,  ,        1M
ota_0,    app,  ota_0,    ,        6M
ota_1,    app,  ota_1,    ,        6M
littlefs, data, spiffs,   ,        2M
```

> Note: LittleFS uses the `spiffs` subtype label for the partition.

### KConfig (sdkconfig highlights)

- Bootloader rollback: `CONFIG_BOOTLOADER_APP_ROLLBACK=y`
- HTTP server WS: `CONFIG_ESP_HTTP_SERVER_ENABLE_WS=y`
- LittleFS: add the `littlefs` component and enable `CONFIG_LITTLEFS_ON_SPI_FLASH=y`
- Brownout: `CONFIG_ESP_BROWNOUT_DET=y`

### Component wiring (CMake)

Top-level `CMakeLists.txt` adds subdirs under `components/`. Each component exports its public headers via `INCLUDE_DIRS`.

Example `components/http_ui/CMakeLists.txt`:

```cmake
idf_component_register(SRCS "http_ui.c"
  INCLUDE_DIRS "include"
  REQUIRES esp_http_server json littlefs vfs msg_bus config_store ota_fw net_apsta)
```

### Net: AP+STA (AP always on, STA optional)

- **AP**: SSID `BOATDASH-<last4MAC>`, WPA2-PSK from NVS (`ap_psk`), channel 1, max 4 clients. DHCP assigns `192.168.4.0/24` with GW `192.168.4.1`.
- **STA**: If `sta_ssid/sta_psk` present, connect to phone hotspot. On `IP_EVENT_STA_GOT_IP` ⇒ start SNTP.
- **Captive portal**: optional minimal DNS redirect (bind UDP 53 and respond `A 192.168.4.1` for any name) to point first hits to `/`.

```c
// net_apsta.h
void net_start_apsta(const char* ap_psk, const char* sta_ssid, const char* sta_psk);
```

```c
// net_apsta.c (excerpt)
static void on_ip_event(void* arg, esp_event_base_t base, int32_t id, void* data){
  if(id==IP_EVENT_STA_GOT_IP){ /* start sntp here */ }
}
void net_start_apsta(const char* ap_psk,const char* sta_ssid,const char* sta_psk){
  esp_netif_init(); esp_event_loop_create_default();
  esp_netif_t* ap = esp_netif_create_default_wifi_ap();
  esp_netif_t* st = esp_netif_create_default_wifi_sta();
  wifi_init_config_t cfg=WIFI_INIT_CONFIG_DEFAULT(); esp_wifi_init(&cfg);
  wifi_config_t ap_cfg={0}; ap_cfg.ap.authmode=WIFI_AUTH_WPA2_PSK; ap_cfg.ap.max_connection=4; ap_cfg.ap.channel=1;
  snprintf((char*)ap_cfg.ap.ssid, sizeof(ap_cfg.ap.ssid), "BOATDASH-%02X%02X", esp_efuse_mac()[4], esp_efuse_mac()[5]);
  strlcpy((char*)ap_cfg.ap.password, ap_psk, sizeof(ap_cfg.ap.password));
  wifi_config_t sta_cfg={0}; sta_cfg.sta.threshold.authmode=WIFI_AUTH_WPA2_PSK;
  if(sta_ssid && *sta_ssid){ strlcpy((char*)sta_cfg.sta.ssid, sta_ssid, sizeof(sta_cfg.sta.ssid)); strlcpy((char*)sta_cfg.sta.password, sta_psk?:"", sizeof(sta_cfg.sta.password)); }
  esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &on_ip_event, NULL);
  esp_wifi_set_mode(WIFI_MODE_APSTA);
  esp_wifi_set_config(WIFI_IF_AP, &ap_cfg);
  if(sta_ssid && *sta_ssid) esp_wifi_set_config(WIFI_IF_STA, &sta_cfg);
  esp_wifi_start(); if(sta_ssid && *sta_ssid) esp_wifi_connect();
}
```

### LittleFS mount

```c
// ui_assets.c
esp_err_t ui_fs_mount(void){
  esp_vfs_littlefs_conf_t conf = {.base_path="/littlefs", .partition_label="littlefs", .format_if_mount_failed=true};
  return esp_vfs_littlefs_register(&conf);
}
```

### HTTP + WebSocket

- Serve `/` and `/lib/*` from LittleFS.
- WS endpoint `/ws` pushes frames every 100–200 ms.
- **OTA restricted to SoftAP**: POST `/ota` only accepts clients from `192.168.4.0/24`.

```c
// http_ui.h
void http_ui_start(void);
void http_ui_broadcast_json(const char* json, size_t len);
bool http_ui_is_request_from_ap(httpd_req_t* req);
```

```c
// http_ui.c (excerpts)
static httpd_handle_t s_server;
static esp_err_t root_get(httpd_req_t* r){ return httpd_resp_sendstr(r, "<!doctype html>... (or serve from file) ..."); }
static esp_err_t ws_handler(httpd_req_t* req){
  if(req->method==HTTP_GET) return ESP_OK; // handshake handled by core
  httpd_ws_frame_t f={.type=HTTPD_WS_TYPE_TEXT};
  httpd_ws_recv_frame(req, &f, 0); // ignore client frames
  return ESP_OK;
}
bool http_ui_is_request_from_ap(httpd_req_t* req){
  int fd = httpd_req_to_sockfd(req);
  struct sockaddr_in peer; socklen_t l=sizeof(peer);
  if(getpeername(fd,(struct sockaddr*)&peer,&l)!=0) return false;
  uint32_t ip = ntohl(peer.sin_addr.s_addr);
  return ( (ip & 0xFFFFFF00u) == 0xC0A80400u ); // 192.168.4.0/24
}
```

### OTA (SoftAP‑only)

```c
// ota_fw.h
esp_err_t ota_handle_upload(httpd_req_t* req);
void ota_mark_valid_on_boot(void); // call once systems healthy
```

```c
// ota_fw.c (excerpt)
esp_err_t ota_handle_upload(httpd_req_t* req){
  if(!http_ui_is_request_from_ap(req)) return httpd_resp_send_err(req, HTTPD_403_FORBIDDEN, "OTA allowed only on SoftAP");
  esp_ota_handle_t h; const esp_partition_t* next = esp_ota_get_next_update_partition(NULL);
  if(!next) return httpd_resp_send_err(req,500,"no partition");
  ESP_ERROR_CHECK(esp_ota_begin(next, OTA_SIZE_UNKNOWN, &h));
  char buf[4096]; int r;
  while((r=httpd_req_recv(req, buf, sizeof(buf)))>0){ ESP_ERROR_CHECK(esp_ota_write(h, buf, r)); }
  if(r<0){ esp_ota_end(h); return httpd_resp_send_err(req,500,"rx error"); }
  ESP_ERROR_CHECK(esp_ota_end(h)); ESP_ERROR_CHECK(esp_ota_set_boot_partition(next));
  httpd_resp_sendstr(req, "OK"); vTaskDelay(pdMS_TO_TICKS(200)); esp_restart(); return ESP_OK;
}
void ota_mark_valid_on_boot(void){ esp_ota_mark_app_valid_cancel_rollback(); }
```

### Sensors (ADC1, °F, NO_SIGNAL)

```c
// sensors_adc.c (excerpts)
static adc_oneshot_unit_handle_t adc1;
static const adc_channel_t CH_BATT=ADC_CHANNEL_0, CH_FUEL=ADC_CHANNEL_1, CH_B1=ADC_CHANNEL_2, CH_B2=ADC_CHANNEL_3, CH_B3=ADC_CHANNEL_4;
static inline float tmp36_f_from_mv(int mv){ return ((mv-500)/10.0f)*9.0f/5.0f + 32.0f; }
```

- Sample at 100 Hz/channel → average 8 → EMA.
- NO_SIGNAL if <50 mV or >3200 mV for 2 s or flatline variance < 1 LSB.
- Publish `EV_SENSORS_10HZ` snapshot with `tempB1/2/3` in **°F** and booleans per channel.

### Tach (PCNT)

- PCNT unit with glitch filter (\~50 µs). Window every 200 ms: `rpm = (Δ / PPR) * 60 / 0.2`. Default **PPR=6**.
- EMA smoothing; engine‑off if Δ=0 for > 2 s.

### Relays

- 3 outputs: NAV, ALL, SPOT. Default **OFF** at boot. `/api/relays` POST body `{nav?:bool, all?:bool, spot?:bool}`.

### WebSocket framing (100–200 ms)

- Build from latest snapshots (sensors, rpm, relays, net). Keys: `rpm`, `battV`, `fuel`, `tempB1/2/3`, `relays{}`, `flags{}`, `net{ap,sta,ntp}`.

### Build & Flash

- `idf.py set-target esp32s3`
- `idf.py menuconfig` (select partition table, enable rollback & WS)
- Flash: `idf.py -p <PORT> flash monitor`
- Upload UI: bundle `/index.html` and libs into LittleFS using an image builder script (component `ui_assets`).



## Milestones

1. **Bring‑up**: IDF 5.4 project, partitions, LittleFS mount, watchdog & brownout.
2. **Networking**: AP+STA stable; captive‑portal DNS (optional); SNTP on STA.
3. **HTTP/UI skeleton**: static `/index.html`, WS `/ws`, status `/status`.
4. **Sensors ADC**: 100 Hz pipeline, °F conversion, NO_SIGNAL, NVS calibration.
5. **Tach PCNT**: PPR config, RPM calc + EMA, engine‑off logic.
6. **Relays**: GPIO + `/api/relays` with auth and safe boot states.
7. **UI graph**: EKG‑style bank temps (°F), max bars, flashing over‑temp.
8. **OTA**: Streaming upload, rollback, **SoftAP‑only gate**.
9. **Config UI**: Set SSIDs, thresholds (warn/over), PPR, calibration.
10. **Resilience**: Power‑loss tests during OTA, brownout behavior, recovery docs.
11. **Field test**: On‑boat validation (noise, harness, thermals), tweak filters.

## Gathering Results

**Acceptance checks**

- SoftAP visible as `BOATDASH-xxxx`; WPA2 works; captive portal redirects.
- UI loads offline; WS updates 5–10 Hz; RPM and gauges respond under load.
- Temps: display in **°F**, thresholds enforced; over‑temp flashes; max bars track.
- Relays switch reliably; safe defaults on reboot.
- OTA only from **192.168.4.0/24**; rollback proven by forced crash test.
- STA to phone hotspot brings **SNTP time** within 60 s; UI badges reflect net state.

**Metrics**

- Loop jitter < 20 ms during WS broadcast.
- ADC effective noise < 5 LSB post‑filter.
- Memory headroom: > 60 kB DRAM, > 1 MB PSRAM free at idle.

## Need Professional Help in Developing Your Architecture?

Please contact me at [sammuti.com](https://sammuti.com) :)
'@ | Set-Content README.md -Encoding UTF8

# Init and push via SSH (requires gh auth login done earlier)
if (-not (Test-Path .git)) { git init | Out-Null }
try { git rev-parse --abbrev-ref HEAD | Out-Null } catch { git checkout -b main | Out-Null }

git add .
if (-not (git log -1 2>$null)) { git commit -m "docs: add SPEC-1 (ESP32S3 SoftAP + OTA)" | Out-Null } else { git commit -am "docs: update SPEC-1" | Out-Null }

try { gh config set git_protocol ssh 2>$null | Out-Null } catch {}

$exists = $false
try { gh repo view "$Owner/$RepoName" 2>$null | Out-Null; $exists=$true } catch {}
if (-not $exists) {
  gh repo create $RepoName --$Visibility --source . --remote origin --push --description "Spec for BoatDash (ESP32-S3, ESP-IDF 5.4)"
} else {
  if (-not (git remote 2>$null | Select-String -SimpleMatch "origin")) { git remote add origin "git@github.com:$Owner/$RepoName.git" }
  git push -u origin main
}

if($OpenWeb){ gh repo view --web }

Write-Host "\nSpec repo ready: $(git config --get remote.origin.url)" -ForegroundColor Green
