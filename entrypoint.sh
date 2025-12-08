#!/usr/bin/env bash
set -e

PUID=${PUID:-99}
PGID=${PGID:-100}
TZ=${TZ:-Etc/UTC}
APP_SCRIPT=${APP_SCRIPT:-/config/print_ticket_api.py}
USB_DEVICE=${USB_DEVICE:-}
DEFAULT_DIR=/opt/tasktix
CUPS_PERSIST_DIR=/config/cups

# ----- Timezone -----
if [ -f "/usr/share/zoneinfo/$TZ" ]; then
  ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
  dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 || true
else
  echo "Warning: TZ '$TZ' not found in /usr/share/zoneinfo, using default."
fi

# ----- App user/group (PUID/PGID) -----
if getent group app >/dev/null 2>&1; then
  groupmod -o -g "$PGID" app
else
  groupadd -o -g "$PGID" app
fi

if id app >/dev/null 2>&1; then
  usermod -o -u "$PUID" -g "$PGID" app
else
  useradd -o -u "$PUID" -g "$PGID" -d /home/app -m app
fi

mkdir -p /config
mkdir -p /var/log/cups /var/run/cups /var/spool/cups

echo "Running as UID: $(id -u app), GID: $(id -g app)"
echo "Time zone: $TZ"

# USB device info (optional)
if [ -n "$USB_DEVICE" ]; then
  if [ -e "$USB_DEVICE" ]; then
    echo "USB_DEVICE '$USB_DEVICE' is present inside container."
  else
    echo "Warning: USB_DEVICE '$USB_DEVICE' not found inside container."
  fi
fi

# ----- Seed /config with default app files on first run -----
if [ ! -f /config/print_ticket_api.py ] && [ -f "$DEFAULT_DIR/print_ticket_api.py" ]; then
  echo "Seeding /config/print_ticket_api.py from image defaults..."
  cp "$DEFAULT_DIR/print_ticket_api.py" /config/
fi

if [ ! -f /config/print_ticket.sh ] && [ -f "$DEFAULT_DIR/print_ticket.sh" ]; then
  echo "Seeding /config/print_ticket.sh from image defaults..."
  cp "$DEFAULT_DIR/print_ticket.sh" /config/
  chmod +x /config/print_ticket.sh
fi

if [ ! -f /config/settings.json ] && [ -f "$DEFAULT_DIR/settings.json" ]; then
  echo "Seeding /config/settings.json from image defaults..."
  cp "$DEFAULT_DIR/settings.json" /config/
fi

# ----- Persist CUPS config under /config/cups/etc -----
mkdir -p "$CUPS_PERSIST_DIR"

# Only do this once: if /etc/cups is not yet a symlink, we haven't set up persistence
if [ ! -L /etc/cups ]; then
  mkdir -p "$CUPS_PERSIST_DIR/etc"

  # Seed persistent CUPS config on first run (if target is empty)
  if [ -z "$(ls -A "$CUPS_PERSIST_DIR/etc" 2>/dev/null)" ]; then
    echo "Seeding persistent CUPS config into /config/cups/etc..."
    cp -a /etc/cups/. "$CUPS_PERSIST_DIR/etc/"
  fi

  # Move original /etc/cups aside (keep a backup) and replace with symlink
  mv /etc/cups /etc/cups.orig
  ln -s "$CUPS_PERSIST_DIR/etc" /etc/cups
fi

# Make /config generally writable by the app user (for scripts, logs, state)
chown -R "$PUID":"$PGID" /config /home/app || true
chmod -R 775 /config || true

# But tighten CUPS config perms so CUPS doesn't complain about insecure permissions
if [ -d "$CUPS_PERSIST_DIR/etc" ]; then
  echo "Tightening permissions on /config/cups/etc for CUPS..."
  chown -R root:root "$CUPS_PERSIST_DIR/etc"
  find "$CUPS_PERSIST_DIR/etc" -type d -exec chmod 755 {} \;
  find "$CUPS_PERSIST_DIR/etc" -type f -exec chmod 644 {} \;
fi

# ----- CUPS admin user setup -----
CUPS_USER="${CUPS_USER:-admin}"
CUPS_PASSWORD="${CUPS_PASSWORD:-adminpass}"

if ! getent group lpadmin >/dev/null; then
  groupadd -r lpadmin
fi

if ! id "$CUPS_USER" >/dev/null 2>&1; then
  useradd -M -s /usr/sbin/nologin -G lpadmin "$CUPS_USER"
else
  usermod -a -G lpadmin "$CUPS_USER"
fi

echo "${CUPS_USER}:${CUPS_PASSWORD}" | chpasswd
echo "CUPS admin user: $CUPS_USER"

# ----- Start CUPS -----
echo "Starting CUPS (cupsd)..."
/usr/sbin/cupsd
sleep 2

# ----- Start application -----
if [ -n "$APP_SCRIPT" ] && [ -f "$APP_SCRIPT" ]; then
  echo "Starting application: $APP_SCRIPT"
  exec gosu app "$@"
else
  echo "APP_SCRIPT '$APP_SCRIPT' not found; keeping container alive."
  tail -f /dev/null
fi

