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
* `static/` holds the Classic page, `static/industrial/` the Industrial one, `static/desert/` the Desert one, `static/arctic/` the Arctic one and `static/redwoods/` the Redwoods one, as vanilla HTML, CSS, and JS. It loads nothing
  from the internet, uses inline SVG icons, and bundles the Inter font
  (SIL OFL, see `static/fonts/OFL.txt`); Desert bundles Ultra (Apache-2.0) and
  Zilla Slab (SIL OFL), see `static/desert/fonts/OFL.txt`; Arctic bundles Exo 2 and
  Barlow Semi Condensed (SIL OFL), see `static/arctic/fonts/OFL.txt`; Redwoods bundles
  National Park and Source Serif 4 (SIL OFL), see `static/redwoods/fonts/OFL.txt`.
* `wxdash.service` is a systemd unit that runs the server as user `kitchen`.
* `kiosk.sh` opens the dashboard in Chromium, full-screen or windowed.
* `updater.py`, `wxdash-update.service`, `wxdash-update.timer`: the self-updater (see below).
* `install.sh`: one-shot installer; `publish.sh`: builds the release files (box only).

## Themes (1.2.0; Desert added in 1.3.0, Arctic in 1.4.0, Redwoods in 1.5.0)

Five looks, picked from **Menu → Theme** on the screen: **Classic** (the original
glass design, `static/`) and **Industrial** (burnt orange and black gauges, LED
digits, clock with seconds, `static/industrial/`), **Desert** (1.3.0, `static/desert/`)
**Arctic** (1.4.0, `static/arctic/`) and **Redwoods** (1.5.0; sun-following sky in 1.5.3, `static/redwoods/`).
The default is Classic.

* Tapping a theme POSTs `{"theme": "..."}` to `/api/settings`; the server saves it to
  `/var/lib/wxdash/settings.json` and every open page reloads into the new theme
  (SSE `settings` event, with `/api/health` as a backup).
* That file lives **outside** `/home/kitchen/wxdash`, so self-updates, rollbacks and
  `install.sh` never change it; it survives reboots and kiosk restarts.
* `/var/lib/wxdash` comes from `StateDirectory=wxdash` in `wxdash.service` (new in
  1.2.0), so **run `install.sh` once** after updating to 1.2.0. Until then a theme
  switch still works but resets to Classic when wxdash restarts (the menu says so).
* `/?theme=classic`, `/?theme=industrial`, `/?theme=desert`, `/?theme=arctic` or `/?theme=redwoods` previews a theme
  without saving it.
* 1.2.1: Industrial Moon panel: the dial is sized to the space it has (it used to spill
  over the line above NEW / FULL on the real screen) and that divider line is gone.
* 1.3.0: new **Desert** theme, selectable from Menu → Theme in all three themes. Desert
  has its own gauges and layout: a sun riding an arc over a mesa for temperature
  (cold-to-hot scale, today's low/high band), a stone star compass with a hawk-feather
  pointer plus a drifting-sand speed bar with tumbleweed and gust flag, canyon rock layers
  for the barometer, clay pots for rain, cracked-earth-to-oasis humidity, rock-art suns
  for UV, the moon rising over a mesa, a dune horizon for the next 12 hours, and a storm
  over a mesa with stacked-stone (cairn) strike counts. Night (8 PM-6 AM; real twilight since 1.5.2) is a starry
  desert sky with glowing readouts. It uses the same live data, SSE, health checks and
  lightning alerts as the other themes. Updating keeps the saved theme (an Industrial
  screen stays Industrial); no service-file change, so the normal self-update is enough.
  Rolling back to 1.2.x while Desert is saved shows Classic (1.2.x doesn't know Desert);
  the saved file isn't changed, so Desert comes back on 1.3.0.
  Design credits (ideas only, no code copied): rejuvenate/lovelace-horizon-card (sun arc),
  ugomeda/d3-liquid-fill-gauge (vessel fill), hmu332233/moon.svg (moon phase),
  gibbonsr4/tempest-dashboard (lightning grouping).
* 1.4.0: new **Arctic** theme (glacier blue, ice white, deep navy, aurora green/teal/violet,
  coral for hot and alerts). Gauges: an aurora ice-crystal temperature arc with a snowflake
  marker, a snowflake compass with an icicle pointer and a blowing-snow speed bar with a
  rolling snowball, an ice-core barometer, frosted rain jars, frost-to-mist humidity,
  snow-glare UV crystals, the moon over snowy peaks, a snowy ridge for the next 12 hours and
  an ice-block strike chart. Gentle motion (aurora, snowfall, twinkling stars, blowing snow)
  uses only transform/opacity, pauses when the page is hidden and stops with Lite mode or
  reduced motion. Same live data, SSE, health checks, night mode and lightning alerts.
  * The Theme menu in all four themes now lists Classic, Industrial, Desert and Arctic as a
    2x2 grid of large buttons (at least 48 px tall on the 800x480 screen).
  * Desert fix: the strike chart, the next-12-hours dunes and the barometer layers now
    redraw when their own box changes size, not only when the whole page does.
  * Demo-only options (`mock_time`, `still`, test values, the recording hook) do nothing
    without `?mock=1`.
  * Updating keeps the saved theme; no service-file change. Rolling back to 1.3.0 while
    Arctic is saved shows Classic (1.3.0 doesn't know Arctic); the saved file isn't changed.
  * Credits: same design ideas as Desert (horizon-card sun arc, liquid-fill vessels,
    moon.svg phase, tempest-dashboard lightning grouping); fonts Exo 2 (NDISCOVER/Exo-2.0)
    and Barlow Semi Condensed (jpt/barlow), both SIL OFL.

* 1.5.7: the mouse pointer is no longer permanently invisible. Every theme starts with it hidden; it
  appears as soon as the mouse moves (or a mouse button / wheel is used) and hides again after about
  3 s idle. Touch never shows it. While visible, Menu, buttons and tappable cards show the hand pointer.
  Shared helper static/cursor.js (passive listeners, one idle timer); the menu's "Show cursor" option
  still keeps it on permanently.
* 1.5.6: Redwoods wind bar: the copper post and pennant are replaced by a copper arrow above the bar
  pointing down at the current speed (gust stays in the Gust now / Max gust stats). Arctic and Desert:
  the gust pennant is now a down-arrow (coral / terracotta) at the gust value. Precipitation chances in
  every theme (Forecast chip, Tomorrow row, Next 12 Hours) use an inline SVG raindrop instead of the
  U+1F4A7 emoji, which the Pi has no font for (it showed as an empty box). Mock-only `?gust=N` previews
  the gust marker.
* 1.5.5: the Lightning card stays on screen after a strike. On Redwoods and Arctic the card's
  strike highlight reused the class name "flash", which those themes also use for the full-screen
  storm-flash layer (hidden, absolutely positioned, opacity 0), so the first live strike hid the whole
  card until the page reloaded. The highlight is now "lt-flash" and clears itself. Every theme also
  cleans strike data before drawing, keeps the last good values if a draw fails, and shows "—" for
  missing values, so bad or partial data can no longer blank the card. New mock scenarios
  `?mock=1&lightning=old|none|broken` and `tools/lightning_test.js` test this.
* 1.5.4: Redwoods sun phases punched so they read at a glance (same solar math as 1.5.3). Dawn has a
  cool blue-gray canopy with a clear rose/peach glow low in the fog and low east shafts; late afternoon
  has warm golden-amber shafts from the west, warm-tinted fog and a golden cast on the bark; dusk carries
  more amber near the horizon before fading to violet; midday stays the bright misty grove. Atmosphere
  wash is baked into the pre-rendered JPGs (no runtime filters). Normal self-update.

* 1.5.3: Redwoods grove follows the sun at the station (same solar math as Desert 1.5.2). Five
  pre-rendered phases crossfade by opacity: moonlit night with stars through the canopy -> dawn
  (cool blue-gray fog warming to soft rose/peach, low east light shafts) -> misty day with brighter
  shafts -> late-afternoon golden shafts from the west -> dusk (deep amber to violet, fog thickening)
  -> night. Night look starts at the end of civil twilight (sun 6 deg below the horizon) instead of
  8 PM-6 AM, falling back to those hours if lat/lon is missing. Rain, fog, drips and storm flash are
  unchanged; motion stays transform/opacity only. `?mock=1&mock_time=HH:MM` previews any phase.
  Desert and the other themes are unchanged; normal self-update.

* 1.5.2: Desert sky follows the sun at the station. The backdrop, the sky behind the
  temperature arc and the moon card's sky are coloured from the sun's real elevation at the
  station's latitude/longitude (from the ini, UTC-based, so the Pi's or browser's own time zone
  doesn't matter; it matches `astro.py` to ~0.01 deg): starry night with twinkles, an occasional
  shooting star and moonlight on the mesas -> dawn (lavender, pink and peach, from civil
  twilight to about an hour after sunrise, sun rising on the left) -> clear desert blue ->
  late-afternoon golden orange (sun sinking on the right) -> dusk (deep orange, magenta and
  purple, first stars) -> night. Phases blend continuously; colours are recalculated once a
  minute (no running animation for that, no filters/blur). The real sun disc moves on an arc
  low over the mesas and fades out when high so it never competes with the temperature sun.
  Desert's night look (darker cards, glowing readouts) now starts when the sun is 6 deg below
  the horizon (end of civil twilight) instead of a fixed 8 PM-6 AM. Twinkles/shooting star stop
  in Lite mode, with reduced motion and while the page is hidden; the heat shimmer pauses
  outside daylight. `?mock=1&mock_time=HH:MM` previews any phase (mock only). Other themes,
  the server and the saved theme are unchanged; normal self-update.

* 1.5.1: Redwoods hero: the tree-ring log slab behind the temperature is gone (as is the
  slate plaque on it). The colored temperature arc stays exactly as before (45 cold-to-hot
  segments, bronze pin at the current temperature, today's low-high band, degree labels),
  and the forest scene, rain, fog and drips now show through inside it, with the big
  current temperature sitting on the forest (larger, with a dark outline and a soft
  static shade behind it for contrast; no blur). Low/High with times, Outdoor now, the
  Feeling badge and the five tiles are unchanged, as are all other cards and themes.
  `img/ring.webp` was removed. Normal self-update; the saved theme is kept.

* 1.5.0: new **Redwoods** theme (a misty coast-redwood grove: bark, fog, oiled redwood
  cards with dark slate plaques, muted forest colours, high-contrast readouts). Gauges: a
  tree-ring slab for temperature with an inlaid scale and a bronze index, a bronze survey
  compass and a speed rule with a bronze slider for wind, a soil core-sample barometer, glass
  rain gauges with bronze caps, dry-bark-to-fog humidity, UV sun discs, the moon over the
  grove, a treeline for the next 12 hours and a river-stone strike chart. Rain
  falls through the trees all the time, gets heavier when the station reports a rain rate,
  and slants with the live wind; fog drifts between the trunks; a close, recent strike
  flashes the sky. Motion uses only transform/opacity, pauses when the page is hidden and
  stops with Lite mode or reduced motion. Night (8 PM-6 AM) is a dark, moonlit grove.
  Same live data, SSE, health checks and lightning alerts. 1.5.0 also contains everything
  from 1.4.0 (Arctic), which was never published on its own.
  * The Theme menu in all five themes lists Classic, Industrial, Desert, Arctic and Redwoods
    as large buttons in a 3 + 2 grid (second row centered; at least 48 px tall on the
    800x480 screen, fits on screen at 800x480 and 1920x1080).
  * Header fix (Redwoods, Arctic, Desert): with a two-digit hour, the Live pill and a recent
    strike badge, the date could run under the Live pill. The pills now always keep their
    full width; the station name and status shorten with "…" instead.
  * The server now serves `.jpg` and `.webp` files from `static/` (Redwoods' textures).
  * Redwoods follows a theme change made on another screen, its demo-only options
    (`mock_time`, `still`, `flash`, `rain_rate`, test values, the recording hook) do nothing
    without `?mock=1`, and its charts redraw when their own box changes size.
  * Updating keeps the saved theme; no service-file change, so the normal self-update is
    enough. Rolling back to 1.4.0/1.3.0 while Redwoods is saved shows Classic (older versions
    don't know Redwoods); the saved file isn't changed, so Redwoods comes back on 1.5.0.
  * Credits (visual ideas and techniques only, no code copied; every image in
    `static/redwoods/img` is generated procedurally, no photos or third-party artwork):
    timpyrkov/procedural-art and gorillasun.de "Radial Perlin Noise and Generative Tree
    Rings" (noise-distorted radial rings, used for the tree-ring slab); twodee "how-to-3d:
    Wood" (perturbed circular/linear oscillation, the oiled-board grain); Liu, Dong, Hašan
    and Marschner, "Simulating the structure and texture of solid wood" (SIGGRAPH Asia 2016;
    earlywood/latewood, pores and sapwood/heartwood colour model); Thuotracy/rain-pureCSS and
    taiypeo/CSS-Rain (GPL-3.0, ideas only; reworked as three depths of tiled rain streaks in a
    wind-rotated wrapper); CSS 3D Lab "Digital rain in pure CSS" (MIT snippet; near layers
    faster than far ones); ugomeda/d3-liquid-fill-gauge (fill level in the rain gauges);
    hmu332233/moon.svg (moon phase); general layout ideas from poblabs/weewx-belchertown and
    neoground/neowx-material. Fonts: National Park (The National Park Project, after the NPS
    routed-wood signs) and Source Serif 4 (Adobe), both SIL OFL, see
    `static/redwoods/fonts/OFL.txt`.

## One-line install / repair (recommended)

```bash
curl -sL https://raw.githubusercontent.com/dodger6/kitchen-weather-display/main/install.sh | sudo bash
#   add  -s -- --close-terminals  after "bash" to also close leftover terminal windows
```

`install.sh` is safe to run again at any time. It downloads `latest.json` and
`wxdash.tgz`, checks the sha256, installs into `/home/kitchen/wxdash` (keeping
any local files that aren't in the archive and saving the old copy as
`/home/kitchen/wxdash.prev`), installs and enables `wxdash.service`,
`wxdash-update.service` and `wxdash-update.timer`, restarts wxdash, makes
sure `~/.config/labwc/autostart` opens the kiosk, relaunches the kiosk, and
prints a summary. It never touches PiConsole or `wfpiconsole.ini`.

## Self-update

* `VERSION` holds the version; `/api/health` reports it.
* The repo has `latest.json` (`{"version": "...", "sha256": "..."}`) next to `wxdash.tgz`.
* `wxdash-update.timer` runs `wxdash-update.service` (root, oneshot) about every
  10 minutes. It runs a root-owned copy of the updater at
  `/usr/local/lib/wxdash/updater.py`, so the `kitchen` user can't change what runs as root.
* The updater installs only a **newer** version, only if the tarball's sha256
  matches `latest.json`, and only if every archive member is a plain file or
  directory under `wxdash/` (no absolute paths, `..`, or links). It backs up
  to `wxdash.prev`, swaps the new files in, `chown`s them to `kitchen`,
  restarts wxdash and waits up to 30 s for `/api/health` to report the new
  version. If that fails it restores `wxdash.prev`, restarts, and skips that
  version until a newer one is published.
* The page checks `/api/health` every 60 s and reloads itself when the version
  changes, so the kiosk shows the new UI without relaunching Chromium.
* Logs: `journalctl -u wxdash-update`. Check now: `sudo systemctl start wxdash-update`.
  Report only: `sudo python3 /usr/local/lib/wxdash/updater.py --check`.
* Changes to the systemd unit files themselves take effect when `install.sh` is run again.
* Publishing (on the box): bump `VERSION`, run `./publish.sh`, and upload
  `wxdash.tgz`, `latest.json` and `install.sh` from `/workspace/wxupload/` to the repo.

## Manual install on the Pi (PiConsole keeps running)

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
`?mock=1&lightning=active` (demo with an active nearby storm; also `old` = storm ended 45 min ago, `none` = no strikes on record, `broken` = partial/null data), `?mock=1&temp=104.5`
(demo with a test temperature, e.g. `104.5`, `-12.3`, `100.0`, or `none`; mock only), `?glass=1`
(frosted-glass blur + drifting background; off by default because the Pi's GPU has to
re-blur every card on every frame, `?glass=0` turns it off again; also in Menu),
`?lite=1` (most minimal: opaque cards), `?cursor=1` (shows
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
| month/year rain, month strikes | `GET /swd/rest/observations/device/{TempestID}?bucket=e` for the month-to-date and year-to-date windows, column 28 (29 with `[System] nc_rain = 1`) summed + today's rain, exactly like PiConsole's default; with `[System] stats_endpoint = 1` it uses `GET /swd/rest/stats/station/{StationID}` instead, as PiConsole does | 30 min, and at each new day |

Station observation values arrive in SI units (°C, m/s, mb, mm, km) and are
converted on the server. The trend and "tendency" wording ("Falling
rapidly" → "Stormy conditions likely"), the rain-rate wording ("Currently
Dry"), and the feels-like wording follow PiConsole's own thresholds.

## Changes in 1.1.2

* The temperature bar on the main card now uses a fixed 0–130 °F scale (-18–54 °C when
  the station is set to Celsius) instead of today's low→high. The full track shows an
  absolute-temperature gradient (blue/cyan when cold, green/yellow around 60–80 °F,
  orange/red past 100 °F), dimmed outside today's low–high segment; the white dot is the
  current temperature. Values outside the scale are clamped to the ends. Tick labels at
  0, 32, 65, 100 and 130 (middle labels hide automatically if they would collide).
  Mock-only preview switch: `?mock=1&tunit=c`.

## Changes in 1.1.1

* Sun icon redrawn to match the Home Assistant weather card exactly (same geometry,
  #ffca28, rays spin once every 12 s, core pulses 1 to 1.06 every 2.2 s). The glow is a
  pre-blurred gradient layer that only fades in and out, so the Pi never repaints it.
* Smooth mode is the default: no `backdrop-filter` on the cards (semi-opaque cards with a
  soft inner gradient instead) and a static background that changes only with the time
  of day / weather. `?glass=1` or Menu, Glass blur brings the old look back.
* `kiosk.sh` runs Chromium natively on Wayland (`--ozone-platform=wayland
  --enable-gpu-rasterization`) whenever a Wayland socket exists, instead of going
  through Xwayland; X11 is only the fallback. `KIOSK_OZONE=x11` forces X11.
* The updater relaunches the kiosk whenever `kiosk.sh` changed since the kiosk was last
  started, so new Chromium flags apply without a reboot (journal: `kiosk: ...`).

