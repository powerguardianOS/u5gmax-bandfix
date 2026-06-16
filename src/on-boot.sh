#!/bin/bash
# on-boot.sh — udm-bandfix persistence script
# Installed to /data/on_boot.d/ — survives Cloud Gateway firmware updates
# Restores the cron job and runs an immediate band check after every reboot

set -euo pipefail

CRON_FILE="/etc/cron.d/udm-bandfix"
SCRIPT_DEST="/data/udm-bandfix/band-fix.sh"
LOG_FILE="/data/udm-bandfix/band-fix.log"

log() {
    printf '[%s] on-boot: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

[ -f "$SCRIPT_DEST" ] || { log "band-fix.sh not found — skipping"; exit 0; }

# Restore cron job if missing (e.g. after firmware update wipes /etc/cron.d/)
if [ ! -f "$CRON_FILE" ]; then
    log "Cron job missing — restoring..."
    cat > "$CRON_FILE" << 'EOF'
# udm-bandfix: hourly enforcement of Odido NL band restrictions
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 * * * * root /data/udm-bandfix/band-fix.sh >> /data/udm-bandfix/band-fix.log 2>&1
EOF
    chmod 644 "$CRON_FILE"
    log "Cron job restored: $CRON_FILE"
fi

# Run immediate fix — UniFi controller resets bands on every reboot
# Wait for modem to come online (MongoDB needs device to be adopted+connected)
log "Waiting for U5G-Max to appear in MongoDB..."
for i in $(seq 1 12); do
    IP=$(mongo --quiet localhost:27117/ace \
        --eval "print(db.device.findOne({model:'UMBBE630'}).ip)" 2>/dev/null | tr -d '\r\n') || true
    if [ -n "$IP" ] && [ "$IP" != "null" ]; then
        log "U5G-Max online at $IP — running band-fix..."
        "$SCRIPT_DEST" >> "$LOG_FILE" 2>&1 || log "band-fix exited with error (will retry via cron)"
        exit 0
    fi
    log "Not ready yet (attempt $i/12) — waiting 10s..."
    sleep 10
done

log "U5G-Max did not appear within 2 minutes — band-fix will run via hourly cron"
