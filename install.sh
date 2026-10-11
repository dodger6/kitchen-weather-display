#!/usr/bin/env bash
# wxdash one-shot installer / repair tool for the Kitchen Pi. Safe to run again.
#
#   curl -sL https://raw.githubusercontent.com/dodger6/kitchen-weather-display/main/install.sh | sudo bash
#   ... | sudo bash -s -- --close-terminals     # also close leftover lxterminal windows at the end
#
# What it does: downloads latest.json + wxdash.tgz, verifies the sha256, installs the
# files into /home/kitchen/wxdash (local files not in the archive are kept, the old
# copy is saved as /home/kitchen/wxdash.prev), installs and enables wxdash.service,
# wxdash-update.service and wxdash-update.timer, restarts wxdash, makes sure the
# labwc autostart opens the kiosk, relaunches the kiosk, and prints a summary.
# It never touches PiConsole or its wfpiconsole.ini.
set -euo pipefail
# Everything is inside { } so bash reads the whole script before running any of it
# (important for curl | bash: no command can swallow the rest of the script from stdin).
{

CLOSE_TERMINALS=0
for a in "$@"; do
  case "$a" in
    --close-terminals) CLOSE_TERMINALS=1 ;;
    -h|--help) sed -n '2,12p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

BASE="${WXDASH_UPDATE_BASE:-https://raw.githubusercontent.com/dodger6/kitchen-weather-display/main}"
BASE="${BASE%/}"
if [ -n "${WXDASH_UPDATE_BASE:-}" ]; then DEFAULT_TGZ="$BASE/wxdash.tgz"
else DEFAULT_TGZ="https://github.com/dodger6/kitchen-weather-display/raw/main/wxdash.tgz"; fi
TGZ_URL="${WXDASH_TARBALL_URL:-$DEFAULT_TGZ}"
KUSER="${WXDASH_USER:-kitchen}"
# The overrides below exist only for testing on another machine.
PORT="${WXDASH_PORT:-8090}"
LIBDIR="${WXDASH_LIBDIR:-/usr/local/lib/wxdash}"
UNITDIR="${WXDASH_UNITDIR:-/etc/systemd/system}"

say()  { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run this with sudo (… | sudo bash)"
command -v python3 >/dev/null || die "python3 not found"
command -v curl >/dev/null || die "curl not found"
getent passwd "$KUSER" >/dev/null || die "user $KUSER does not exist"
KHOME="${WXDASH_HOME_DIR:-$(getent passwd "$KUSER" | cut -d: -f6)}"
KUID="$(id -u "$KUSER")"
KGROUP="$(id -gn "$KUSER")"
APP="$KHOME/wxdash"

TMP="$(mktemp -d /tmp/wxdash-install.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- download + verify
say "Downloading latest.json"
curl -fsSL --retry 3 -o "$TMP/latest.json" "$BASE/latest.json" || die "could not download $BASE/latest.json"
read -r VERSION SHA < <(python3 - "$TMP/latest.json" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))
v, s = str(m.get("version", "")), str(m.get("sha256", "")).lower()
if not re.fullmatch(r"\d+(\.\d+){0,3}", v) or not re.fullmatch(r"[0-9a-f]{64}", s):
    sys.exit("latest.json is malformed")
print(v, s)
PY
) || die "latest.json is malformed"
echo "    version $VERSION"

say "Downloading wxdash.tgz"
curl -fsSL --retry 3 -o "$TMP/wxdash.tgz" "$TGZ_URL" || die "could not download $TGZ_URL"
GOT="$(sha256sum "$TMP/wxdash.tgz" | cut -d' ' -f1)"
[ "$GOT" = "$SHA" ] || die "sha256 mismatch (expected $SHA, got $GOT). Nothing was installed. (GitHub can lag a few minutes after a publish; try again shortly.)"
echo "    sha256 verified: $SHA"

# Unpack only updater.py + unit files first (the updater itself validates the whole
# archive again before installing anything into $APP).
mkdir -p "$TMP/x"
python3 - "$TMP/wxdash.tgz" "$TMP/x" <<'PY'
import os, sys, tarfile
tgz, dest = sys.argv[1], sys.argv[2]
want = {"wxdash/updater.py", "wxdash/wxdash.service", "wxdash/wxdash-update.service", "wxdash/wxdash-update.timer"}
with tarfile.open(tgz, "r:gz") as tf:
    for m in tf.getmembers():
        n = m.name
        parts = n.split("/")
        if n.startswith("/") or ".." in parts or parts[0] != "wxdash" or not (m.isfile() or m.isdir()):
            sys.exit(f"unsafe archive member: {n!r}")
        if n in want:
            with tf.extractfile(m) as src, open(os.path.join(dest, os.path.basename(n)), "wb") as out:
                out.write(src.read())
missing = [w for w in want if not os.path.exists(os.path.join(dest, os.path.basename(w)))]
if missing:
    sys.exit(f"archive is missing {missing}")
PY

# ---------------------------------------------------------------- root-owned updater + units
say "Installing updater and systemd units"
install -d -o root -g root -m 0755 "$LIBDIR"
install -o root -g root -m 0755 "$TMP/x/updater.py" "$LIBDIR/updater.py"
for u in wxdash.service wxdash-update.service wxdash-update.timer; do
  sed -e "s#/home/kitchen#$KHOME#g" -e "s#^User=kitchen#User=$KUSER#" -e "s#^Group=kitchen#Group=$KGROUP#" \
      "$TMP/x/$u" > "$TMP/x/$u.out"
  install -o root -g root -m 0644 "$TMP/x/$u.out" "$UNITDIR/$u"
  echo "    $UNITDIR/$u"
done
systemctl daemon-reload
systemctl enable wxdash.service >/dev/null 2>&1

# ---------------------------------------------------------------- files (backup, swap, restart, health, rollback)
say "Installing wxdash $VERSION into $APP"
UPDATE_RC=0
WXDASH_INSTALL_DIR="$APP" WXDASH_OWNER="$KUSER:$KGROUP" WXDASH_LOCK="$TMP/lock" \
WXDASH_HEALTH_URL="http://127.0.0.1:$PORT/api/health" WXDASH_SELF_PATH=- WXDASH_KIOSK_RELAUNCH=0 \
  python3 "$LIBDIR/updater.py" --force --tarball "$TMP/wxdash.tgz" --sha256 "$SHA" --version "$VERSION" \
  || UPDATE_RC=$?
chmod +x "$APP/kiosk.sh" 2>/dev/null || true

systemctl enable --now wxdash-update.timer >/dev/null 2>&1

# ---------------------------------------------------------------- kiosk autostart
say "Checking kiosk autostart"
AUTOSTART="$KHOME/.config/labwc/autostart"
KIOSK_LINE="$APP/kiosk.sh &"
install -d -o "$KUSER" -g "$KGROUP" "$KHOME/.config" "$KHOME/.config/labwc"
if [ -f "$AUTOSTART" ] && grep -Eq "wxdash/kiosk\.sh|localhost:$PORT" "$AUTOSTART"; then
  echo "    already present in $AUTOSTART"
else
  [ -f "$AUTOSTART" ] && [ -s "$AUTOSTART" ] && [ "$(tail -c1 "$AUTOSTART")" != "" ] && echo >> "$AUTOSTART"
  echo "$KIOSK_LINE" >> "$AUTOSTART"
  chown "$KUSER:$KGROUP" "$AUTOSTART"
  echo "    added '$KIOSK_LINE' to $AUTOSTART"
fi

# ---------------------------------------------------------------- relaunch kiosk
say "Relaunching the kiosk"
RUNDIR="/run/user/$KUID"
WL=""
for w in wayland-0 wayland-1; do [ -S "$RUNDIR/$w" ] && { WL="$w"; break; }; done
KIOSK_STATE="skipped (no graphical session for $KUSER)"
if [ -d "$RUNDIR" ] && { [ -n "$WL" ] || [ -S /tmp/.X11-unix/X0 ]; }; then
  pkill -u "$KUSER" -f 'wxdash-chromium' 2>/dev/null || true
  for _ in $(seq 1 10); do pgrep -u "$KUSER" -f 'wxdash-chromium' >/dev/null || break; sleep 0.5; done
  # kiosk.sh picks native Wayland when WAYLAND_DISPLAY points at a live socket, else X11.
  if [ -n "$WL" ]; then KENV=(XDG_RUNTIME_DIR="$RUNDIR" WAYLAND_DISPLAY="$WL")
  else KENV=(XDG_RUNTIME_DIR="$RUNDIR" DISPLAY=:0); fi
  sudo -u "$KUSER" -H env "${KENV[@]}" \
    setsid -f "$APP/kiosk.sh" </dev/null >/dev/null 2>&1 || true
  KIOSK_STATE="relaunched"
  sleep 4
  pgrep -u "$KUSER" -f 'wxdash-chromium' >/dev/null && KIOSK_STATE="running" || KIOSK_STATE="launched (still starting)"
fi
echo "    kiosk: $KIOSK_STATE"

# ---------------------------------------------------------------- summary
HEALTH="$(curl -fs --max-time 5 "http://127.0.0.1:$PORT/api/health" || echo 'no response')"
INST_VER="$(cat "$APP/VERSION" 2>/dev/null || echo '?')"
NEXT="$(systemctl list-timers --all --no-legend wxdash-update.timer 2>/dev/null | awk '{print $1" "$2" "$3" "$4}' | head -1)"
cat <<SUM

==================== wxdash install summary ====================
  version installed : $INST_VER   (published: $VERSION)
  sha256            : $SHA
  wxdash.service    : $(systemctl is-active wxdash 2>/dev/null || true), $(systemctl is-enabled wxdash 2>/dev/null || true)
  update timer      : $(systemctl is-active wxdash-update.timer 2>/dev/null || true), $(systemctl is-enabled wxdash-update.timer 2>/dev/null || true)  (next check: ${NEXT:-?})
  health            : $HEALTH
  kiosk             : $KIOSK_STATE
  backup            : $( [ -d "$APP.prev" ] && echo "$APP.prev" || echo none )
  logs              : journalctl -u wxdash -u wxdash-update
=================================================================
SUM
if [ "$UPDATE_RC" -ne 0 ]; then
  echo "WARNING: the new version did not pass its health check (updater exit $UPDATE_RC); see the log above." >&2
fi

if [ "$CLOSE_TERMINALS" -eq 1 ]; then
  echo "Closing lxterminal windows in 3 seconds…"
  setsid -f bash -c "sleep 3; pkill -u '$KUSER' -x lxterminal" </dev/null >/dev/null 2>&1 || true
fi
exit "$UPDATE_RC"
}
