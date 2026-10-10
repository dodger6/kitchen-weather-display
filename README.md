# wxdash: a modern weather display for the Kitchen Pi

wxdash replaces the look of WeatherFlow PiConsole with a modern, high-contrast
dashboard drawn in Chromium. It reads **the same `wfpiconsole.ini`** that
PiConsole already uses, so you don't need to configure anything new. It runs
**alongside** PiConsole, which stays untouched and keeps working until you
decide to switch.

* `server.py` uses only the Python 3.11 standard library (no pip installs).
  It polls the WeatherFlow REST API, computes the derived values, and serves
  the page plus `/api/data` on port 8090.
* `live.py` keeps a live WebSocket open to WeatherFlow (a minimal stdlib
  RFC 6455 client, so no pip installs and no venv needed) and pushes updates
  to the page with Server-Sent Events.
* `astro.py` computes sun and moon rise/set, moon phase, and next new/full
  moon locally in pure Python, with no `ephem` dependency.
* `static/` holds the page as vanilla HTML, CSS, and JS. It loads nothing
  from the internet, uses inline SVG icons, and bundles the Inter font
  (SIL OFL, see `static/fonts/OFL.txt`).
* `wxdash.service` is a systemd unit that runs the server as user `kitchen`.
* `kiosk.sh` opens the dashboard in Chromium, full-screen or windowed.

## Install on the Pi (PiConsole keeps running)

```bash
# 1. copy the files
mkdir -p /home/kitchen/wxdash
tar -xzf wxdash.tar.gz -C /home/kitchen          # creates /home/kitchen/wxdash
chmod +x /home/kitchen/wxdash/kiosk.sh

# 2. quick test with demo data (no API calls)
python3 /home/kitchen/wxdash/server.py --mock
#    open http://localhost:8090 (or http://<pi-ip>:8090 from another device), then Ctrl+C

# 3. quick test with live data, using PiConsole's ini
python3 /home/kitchen/wxdash/server.py --ini /home/kitchen/wfpiconsole/wfpiconsole.ini

# 4. run it as a service (starts at boot; does NOT touch PiConsole)
sudo cp /home/kitchen/wxdash/wxdash.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wxdash
systemctl status wxdash --no-pager
journalctl -u wxdash -f          # logs (the token is never logged)

# 5. look at it
WINDOWED=1 /home/kitchen/wxdash/kiosk.sh   # in a window on the Pi desktop, over/next to PiConsole
#   or full-screen:  /home/kitchen/wxdash/kiosk.sh   (press Alt+F4 to exit)
```

Nothing above stops, disables, or edits PiConsole or its ini. wxdash only
**reads** `wfpiconsole.ini`.

### Optional: make it the kitchen screen (only after you approve the look)

Add an autostart entry for `kiosk.sh`. On Raspberry Pi OS bookworm with
labwc, append this line to `~/.config/labwc/autostart`:

```
/home/kitchen/wxdash/kiosk.sh &
```

On wayfire, add `wxdash = /home/kitchen/wxdash/kiosk.sh` under `[autostart]`
in `~/.config/wayfire.ini`. Whether PiConsole also starts is a separate
decision; this README doesn't change it.

### Uninstall

```bash
sudo systemctl disable --now wxdash && sudo rm /etc/systemd/system/wxdash.service
rm -rf /home/kitchen/wxdash ~/.config/wxdash-chromium
```

## Options

| flag / env | default | meaning |
|---|---|---|
| `--ini` / `WXDASH_INI` | `/home/kitchen/wfpiconsole/wfpiconsole.ini` | PiConsole config to read |
| `--port` / `WXDASH_PORT` | `8090` | HTTP port |
| `--host` / `WXDASH_HOST` | `0.0.0.0` | use `127.0.0.1` to allow only the Pi itself |
| `--mock` | off | serve built-in example data and make no network calls; simulates rapid_wind every 3 s and an occasional strike |
| `--no-websocket` / `WXDASH_NO_WS=1` | off | REST polling only (no live WeatherFlow WebSocket) |

Page URL options: `?mock=1` (demo data for this page only),
`?mock=1&lightning=active` (demo with an active nearby storm), `?mock=1&temp=104.5`
(demo with a test temperature, e.g. `104.5`, `-12.3`, `100.0`, or `none`; mock only), `?lite=1`
(turns off the glass blur if Chromium is ever sluggish), `?cursor=1` (shows
the mouse pointer), `?stream=0` (polling only, no live stream),
`?panel=sager|menu` (opens a panel).

## Live updates (like PiConsole)

* The server opens `wss://ws.weatherflow.com/swd/data` with the ini token and
  sends `listen_start` and `listen_rapid_start` for `[Station] TempestID`.
* `rapid_wind` (about every 3 s) moves the wind needle and speed smoothly,
  `obs_st` (every minute) refreshes temperature, humidity, pressure, UV,
  solar, wind and rain, and `evt_strike` updates the Lightning card at once
  and flashes the ⚡.
* The client sends a WebSocket ping every 30 s, reconnects after 90 s of
  silence, and backs off 2 s → 4 s → … → 2 min between reconnect attempts.
* The browser gets updates from `GET /api/stream` (Server-Sent Events:
  `data`, `wind`, `strike`, `live` events, plus a keepalive comment every
  15 s). The token never reaches the browser. If the stream drops, the page
  falls back to polling `/api/data` every 15 s and the browser reconnects
  the stream by itself.
* REST polling keeps running the whole time, so if the WebSocket can't
  connect the dashboard still works as a polled display.
* The header pill shows **Live** (green) when the WebSocket feed is connected
  and streaming to the page, **Reconnecting** (amber), or **Polling** (gray).

Test it without the real service: `python3 tools/fake_wf.py` starts a fake
WeatherFlow (REST on :8771, WebSocket on :8772), then run
`WXDASH_API_BASE=http://127.0.0.1:8771 WXDASH_WS_URL=ws://127.0.0.1:8772/swd/data python3 server.py --ini tools/fake.ini --port 8091`.

## Lightning card

The Lightning card is always on the main screen. It shows the last strike
distance and when it happened, counts for the last hour, last 3 hours,
today and this month, a status line ("No strikes nearby", or "Active —
strikes within X mi" with a glowing ⚡ for 30 minutes after a strike), and
a bar chart of strikes per hour over the last 24 hours, built from the
Tempest's own history (column 15 of the bucket `a` device observations) plus
live `evt_strike` messages. `/api/data` returns those buckets as
`lightning.hourly` (`time`, `count`, `min_distance`), oldest first.

## What it reads from the ini

The key names match PiConsole's `lib/config.py`:
`[Keys] WeatherFlow` (the API token), `[Station] StationID`, `TempestID`,
`Latitude`, `Longitude`, `Timezone`, `Name`, `[Units] Temp/Wind/Pressure/Precip/Distance`,
`[Display] TimeFormat`, and `[FeelsLike]` cut-offs.
The server re-reads the ini every poll cycle, so fixing a bad ini recovers
without a restart.

## How the token is protected

* The token is read from the ini into server memory only.
* It's used only for outbound HTTPS calls to `swd.weatherflow.com` and the
  outbound WebSocket to `ws.weatherflow.com`.
* `/api/data` and `/api/stream` contain no token, URL, or ini content, only weather values.
* Error messages are generic ("API token rejected (401)") and are also
  passed through a scrubber that replaces the token with `***`.
* The HTTP request log is disabled, and outbound URLs are never logged.
* The static file server serves only files inside `static/` with
  whitelisted extensions, so `/../server.py` or the ini can't be fetched.
* The systemd unit runs as `kitchen` with `ProtectSystem=strict` and a
  read-only home.

## Data sources

| what | endpoint | interval |
|---|---|---|
| current observation | `GET /swd/rest/observations/station/{StationID}` | 60 s |
| forecast | `GET /swd/rest/better_forecast?station_id=…&units_temp=f&units_wind=mph&units_pressure=mb&units_precip=in&units_distance=mi` | 10 min |
| 24 h history (hi/lo + times, 24 h diff, 3 h trends, avg wind, max gust, strikes today) | `GET /swd/rest/observations/device/{TempestID}?bucket=a&time_start=…&time_end=…` | 10 min |
| month/year rain, month strikes | `GET /swd/rest/stats/station/{StationID}` (the same call PiConsole makes) | 30 min |

Station observation values arrive in SI units (°C, m/s, mb, mm, km) and are
converted on the server. The trend and "tendency" wording ("Falling
rapidly" → "Stormy conditions likely"), the rain-rate wording ("Currently
Dry"), and the feels-like wording follow PiConsole's own thresholds.
