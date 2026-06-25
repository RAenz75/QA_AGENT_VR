#!/usr/bin/env bash
# Surveille la stabilité de l'app en continu via logcat (crashes, ANR, OOM).
# Écrit les incidents dans les logs et les alertes dans alerts.queue.
# Usage : ./watch_stability.sh <APP_PACKAGE> <SESSION_ID>
# Arrêt  : envoyer SIGTERM au process (PID dans output/<SESSION_ID>/logs/watcher.pid)

set -euo pipefail

APP_PACKAGE="${1:?Usage: $0 <APP_PACKAGE> <SESSION_ID>}"
SESSION_ID="${2:?Usage: $0 <APP_PACKAGE> <SESSION_ID>}"
SESSION_DIR="output/${SESSION_ID}"
STATUS_FILE="${SESSION_DIR}/agent_status/stability-watcher.json"
ALERTS_FILE="${SESSION_DIR}/alerts.queue"
INCIDENTS_LOG="${SESSION_DIR}/logs/incidents.log"
CRITICAL_LOG="${SESSION_DIR}/logs/logcat_critical.log"

CRASH_COUNT=0
ANR_COUNT=0
OOM_COUNT=0
ALERT_LEVEL="ok"

_update_status() {
    cat > "$STATUS_FILE" << EOF
{
  "agent": "stability-watcher",
  "status": "running",
  "last_update": "$(date +%H:%M:%S)",
  "summary": "${CRASH_COUNT} crash — ${ANR_COUNT} ANR — ${OOM_COUNT} OOM — surveillance active",
  "alert_level": "${ALERT_LEVEL}"
}
EOF
}

_alert() {
    local level="$1" msg="$2"
    echo "[$(date +%H:%M:%S)][stability-watcher][${level}] ${msg}" >> "$ALERTS_FILE"
    echo "[$(date +%H:%M:%S)] ${msg}" >> "$INCIDENTS_LOG"
}

_screenshot() {
    local tag="$1"
    local ts; ts=$(date +%H%M%S)
    adb shell screencap -p "/sdcard/${tag}_${ts}.png" 2>/dev/null && \
        adb pull "/sdcard/${tag}_${ts}.png" "${SESSION_DIR}/screenshots/" 2>/dev/null || true
}

_collect_post_incident() {
    local ts="$1"
    adb shell dumpsys activity > "${SESSION_DIR}/logs/dumpsys_activity_${ts}.log" 2>/dev/null || true
    adb shell dumpsys meminfo > "${SESSION_DIR}/logs/meminfo_${ts}.log" 2>/dev/null || true
    adb shell dumpsys battery >> "$INCIDENTS_LOG" 2>/dev/null || true
    adb shell uptime >> "$INCIDENTS_LOG" 2>/dev/null || true
}

# ── 1. Logcat filtré sur les événements critiques ─────────────────────────────
echo "[watch_stability] Démarrage de la surveillance logcat..."
_update_status

adb logcat -c 2>/dev/null || true  # vider le buffer

adb logcat -v time | grep --line-buffered -E \
    "AndroidRuntime|FATAL EXCEPTION|ANR in|OutOfMemoryError|onLowMemory|beginning of crash|\*\*\* \*\*\* \*\*\*" \
    > "$CRITICAL_LOG" &
PID_LOGCAT=$!

# Logcat global app (par PID)
APP_PID=$(adb shell pidof "$APP_PACKAGE" 2>/dev/null | tr -d '\r' || echo "")
if [ -n "$APP_PID" ]; then
    adb logcat --pid="$APP_PID" -v threadtime > "${SESSION_DIR}/logs/logcat_app.log" &
    PID_APP_LOG=$!
else
    PID_APP_LOG=0
fi

adb logcat -v threadtime "*:E" AndroidRuntime:E ActivityManager:I > "${SESSION_DIR}/logs/logcat_system.log" &
PID_SYS_LOG=$!

echo "$PID_LOGCAT $PID_APP_LOG $PID_SYS_LOG" > "${SESSION_DIR}/logs/watcher.pid"

# ── 2. Boucle de détection des incidents ─────────────────────────────────────
_loop_detect() {
    local last_size=0
    while true; do
        sleep 5

        if [ ! -f "$CRITICAL_LOG" ]; then continue; fi
        local current_size; current_size=$(wc -c < "$CRITICAL_LOG")
        if [ "$current_size" -le "$last_size" ]; then continue; fi

        # Lire les nouvelles lignes
        local new_lines; new_lines=$(tail -c "+$((last_size + 1))" "$CRITICAL_LOG")
        last_size=$current_size

        local ts; ts=$(date +%H%M%S)

        # Crash Java
        if echo "$new_lines" | grep -q "FATAL EXCEPTION"; then
            CRASH_COUNT=$(( CRASH_COUNT + 1 ))
            ALERT_LEVEL="critical"
            adb logcat -d -t 100 > "${SESSION_DIR}/logs/crash_dump_${ts}.log" 2>/dev/null || true
            _screenshot "CRASH"
            _collect_post_incident "$ts"
            _alert "CRITICAL" "CRASH Java détecté — voir logs/crash_dump_${ts}.log"
        fi

        # Crash natif
        if echo "$new_lines" | grep -q "\*\*\* \*\*\* \*\*\*\|\beginning of crash"; then
            CRASH_COUNT=$(( CRASH_COUNT + 1 ))
            ALERT_LEVEL="critical"
            adb logcat -d -t 100 > "${SESSION_DIR}/logs/crash_native_${ts}.log" 2>/dev/null || true
            _screenshot "CRASH_NATIVE"
            _collect_post_incident "$ts"
            _alert "CRITICAL" "CRASH natif détecté — voir logs/crash_native_${ts}.log"
        fi

        # ANR
        if echo "$new_lines" | grep -q "ANR in"; then
            ANR_COUNT=$(( ANR_COUNT + 1 ))
            [ "$ALERT_LEVEL" = "critical" ] || ALERT_LEVEL="warning"
            adb shell cat /data/anr/traces.txt > "${SESSION_DIR}/logs/anr_traces_${ts}.log" 2>/dev/null || true
            _screenshot "ANR"
            _collect_post_incident "$ts"
            _alert "WARNING" "ANR détecté dans ${APP_PACKAGE}"
        fi

        # OOM
        if echo "$new_lines" | grep -q "OutOfMemoryError\|onLowMemory"; then
            OOM_COUNT=$(( OOM_COUNT + 1 ))
            echo "[$(date +%H:%M:%S)] OOM/LowMemory détecté" >> "${SESSION_DIR}/logs/memory_warnings.log"
            _alert "WARNING" "OutOfMemoryError ou onLowMemory détecté"
        fi

        _update_status
    done
}

# ── 3. Boucle de santé du processus (toutes les 60s) ─────────────────────────
_loop_health() {
    while true; do
        sleep 60
        local pid; pid=$(adb shell pidof "$APP_PACKAGE" 2>/dev/null | tr -d '\r' || echo "")
        if [ -z "$pid" ]; then
            ALERT_LEVEL="critical"
            _alert "CRITICAL" "PROCESSUS MORT — ${APP_PACKAGE} fermé de façon inattendue"
        fi
        _update_status
    done
}

_loop_detect &  PID_DETECT=$!
_loop_health &  PID_HEALTH=$!

echo "[watch_stability] ✅ Surveillance active (PIDs logcat:$PID_LOGCAT detect:$PID_DETECT health:$PID_HEALTH)"

trap "kill $PID_LOGCAT $PID_APP_LOG $PID_SYS_LOG $PID_DETECT $PID_HEALTH 2>/dev/null
      cat > '$STATUS_FILE' << 'EOF'
{\"agent\":\"stability-watcher\",\"status\":\"done\",\"last_update\":\"$(date +%H:%M:%S)\",\"summary\":\"${CRASH_COUNT} crash — ${ANR_COUNT} ANR — session terminée\",\"alert_level\":\"${ALERT_LEVEL}\"}
EOF
      echo '[watch_stability] Surveillance arrêtée.'" EXIT
wait
