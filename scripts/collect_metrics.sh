#!/usr/bin/env bash
# Collecte en continu FPS, mémoire et CPU dans des CSV.
# Lance les 3 boucles en background et écrit le statut pour l'orchestrateur.
# Usage : ./collect_metrics.sh <APP_PACKAGE> <SESSION_ID>
# Arrêt  : envoyer SIGTERM au process (PID dans output/<SESSION_ID>/metrics/collector.pid)

set -euo pipefail

APP_PACKAGE="${1:?Usage: $0 <APP_PACKAGE> <SESSION_ID>}"
SESSION_ID="${2:?Usage: $0 <APP_PACKAGE> <SESSION_ID>}"
SESSION_DIR="output/${SESSION_ID}"
STATUS_FILE="${SESSION_DIR}/agent_status/perf-monitor.json"
ALERTS_FILE="${SESSION_DIR}/alerts.queue"

# Compteurs pour la détection de seuils consécutifs
FPS_LOW_COUNT=0
CPU_HIGH_COUNT=0
ALERT_LEVEL="ok"

_update_status() {
    local summary="$1"
    cat > "$STATUS_FILE" << EOF
{
  "agent": "perf-monitor",
  "status": "running",
  "last_update": "$(date +%H:%M:%S)",
  "summary": "${summary}",
  "alert_level": "${ALERT_LEVEL}"
}
EOF
}

_alert() {
    local level="$1" msg="$2"
    echo "[$(date +%H:%M:%S)][perf-monitor][${level}] ${msg}" >> "$ALERTS_FILE"
    echo "[$(date +%H:%M:%S)][perf-monitor][${level}] ${msg}" >> "${SESSION_DIR}/metrics/alerts.log"
}

# ── CSV Headers ───────────────────────────────────────────────────────────────
FPS_CSV="${SESSION_DIR}/metrics/fps_data.csv"
MEM_CSV="${SESSION_DIR}/metrics/memory_data.csv"
CPU_CSV="${SESSION_DIR}/metrics/cpu_data.csv"
echo "timestamp,total_frames,janky_frames,janky_pct,p50_ms,p90_ms,p95_ms,p99_ms" > "$FPS_CSV"
echo "timestamp,total_rss_kb,native_heap_kb,java_heap_kb,graphics_kb" > "$MEM_CSV"
echo "timestamp,cpu_pct" > "$CPU_CSV"

# ── Boucle FPS (toutes les 10s) ───────────────────────────────────────────────
_loop_fps() {
    local low_count=0
    while true; do
        local ts; ts=$(date +%H:%M:%S)
        adb shell dumpsys gfxinfo "$APP_PACKAGE" reset > /dev/null 2>&1
        sleep 10
        local raw; raw=$(adb shell dumpsys gfxinfo "$APP_PACKAGE" 2>/dev/null)

        local total; total=$(echo "$raw" | grep "Total frames rendered" | grep -o '[0-9]*' | head -1)
        local janky; janky=$(echo "$raw" | grep "Janky frames" | grep -o '[0-9]*' | head -1)
        local p50; p50=$(echo "$raw" | grep "50th percentile" | grep -o '[0-9]*ms' | head -1 | tr -d 'ms')
        local p90; p90=$(echo "$raw" | grep "90th percentile" | grep -o '[0-9]*ms' | head -1 | tr -d 'ms')
        local p95; p95=$(echo "$raw" | grep "95th percentile" | grep -o '[0-9]*ms' | head -1 | tr -d 'ms')
        local p99; p99=$(echo "$raw" | grep "99th percentile" | grep -o '[0-9]*ms' | head -1 | tr -d 'ms')

        total="${total:-0}"; janky="${janky:-0}"
        local janky_pct=0
        if [ "$total" -gt 0 ]; then
            janky_pct=$(( janky * 100 / total ))
        fi

        echo "$ts,$total,$janky,$janky_pct,${p50:-0},${p90:-0},${p95:-0},${p99:-0}" >> "$FPS_CSV"

        # FPS approximé : total frames / 10s = fps
        local fps=$(( total / 10 ))
        if [ "$fps" -lt 30 ]; then
            low_count=$(( low_count + 1 ))
            if [ "$low_count" -ge 3 ]; then
                ALERT_LEVEL="critical"
                _alert "CRITICAL" "FPS=${fps} pendant 3 cycles consécutifs"
                adb shell screencap -p /sdcard/fps_critical_$(date +%H%M%S).png && \
                    adb pull /sdcard/fps_critical_$(date +%H%M%S).png "${SESSION_DIR}/screenshots/" 2>/dev/null || true
                low_count=0
            fi
        elif [ "$fps" -lt 60 ]; then
            _alert "WARNING" "FPS=${fps} en dessous du seuil (60 fps)"
            low_count=0
        else
            low_count=0
            [ "$ALERT_LEVEL" = "ok" ] || ALERT_LEVEL="ok"
        fi
    done
}

# ── Boucle mémoire (toutes les 30s) ──────────────────────────────────────────
_loop_memory() {
    while true; do
        local ts; ts=$(date +%H:%M:%S)
        local raw; raw=$(adb shell dumpsys meminfo "$APP_PACKAGE" 2>/dev/null)

        local rss; rss=$(echo "$raw" | grep "TOTAL RSS" | grep -o '[0-9]*' | head -1)
        local native; native=$(echo "$raw" | grep "Native Heap" | grep -o '[0-9]*' | head -1)
        local java; java=$(echo "$raw" | grep "Java Heap" | grep -o '[0-9]*' | head -1)
        local gfx; gfx=$(echo "$raw" | grep "Graphics" | grep -o '[0-9]*' | head -1)

        rss="${rss:-0}"; native="${native:-0}"; java="${java:-0}"; gfx="${gfx:-0}"
        echo "$ts,$rss,$native,$java,$gfx" >> "$MEM_CSV"

        local rss_mb=$(( rss / 1024 ))
        if [ "$rss_mb" -gt 2000 ]; then
            ALERT_LEVEL="critical"
            _alert "CRITICAL" "Mémoire RSS=${rss_mb}MB — seuil critique (>2GB) dépassé"
        elif [ "$rss_mb" -gt 1500 ]; then
            [ "$ALERT_LEVEL" = "critical" ] || ALERT_LEVEL="warning"
            _alert "WARNING" "Mémoire RSS=${rss_mb}MB — seuil alerte (>1.5GB) dépassé"
        fi

        sleep 30
    done
}

# ── Boucle CPU (toutes les 10s) ───────────────────────────────────────────────
_loop_cpu() {
    local high_count=0
    while true; do
        local ts; ts=$(date +%H:%M:%S)
        local cpu; cpu=$(adb shell top -n 1 -b 2>/dev/null | grep "$APP_PACKAGE" | awk '{print $9}' | head -1 | tr -d '%')
        cpu="${cpu:-0}"
        echo "$ts,$cpu" >> "$CPU_CSV"

        if [ "$cpu" -gt 85 ]; then
            high_count=$(( high_count + 1 ))
            if [ "$high_count" -ge 5 ]; then
                ALERT_LEVEL="critical"
                _alert "CRITICAL" "CPU=${cpu}% pendant 5 cycles consécutifs"
                high_count=0
            fi
        elif [ "$cpu" -gt 60 ]; then
            _alert "WARNING" "CPU=${cpu}% — seuil alerte (>60%) dépassé"
            high_count=0
        else
            high_count=0
        fi

        sleep 10
    done
}

# ── Boucle de statut (toutes les 15s) ─────────────────────────────────────────
_loop_status() {
    while true; do
        local fps_last; fps_last=$(tail -1 "$FPS_CSV" 2>/dev/null | cut -d',' -f1)
        local mem_last; mem_last=$(tail -1 "$MEM_CSV" 2>/dev/null | awk -F',' '{mb=int($2/1024); print mb"MB RSS"}')
        local cpu_last; cpu_last=$(tail -1 "$CPU_CSV" 2>/dev/null | cut -d',' -f2)
        _update_status "FPS collecté ${fps_last:-?} — ${mem_last:-?} — CPU=${cpu_last:-?}%"
        sleep 15
    done
}

# ── Lancement en background ───────────────────────────────────────────────────
_update_status "Démarrage de la collecte..."

_loop_fps &   PID_FPS=$!
_loop_memory & PID_MEM=$!
_loop_cpu &   PID_CPU=$!
_loop_status & PID_STATUS=$!

echo "$PID_FPS $PID_MEM $PID_CPU $PID_STATUS" > "${SESSION_DIR}/metrics/collector.pid"
echo "[collect_metrics] ✅ Collecte démarrée (PIDs: $PID_FPS $PID_MEM $PID_CPU $PID_STATUS)"
echo "[collect_metrics] Arrêt : kill \$(cat ${SESSION_DIR}/metrics/collector.pid) ou ./stop_session.sh ${SESSION_ID}"

# Garder le script actif pour recevoir SIGTERM
trap "kill $PID_FPS $PID_MEM $PID_CPU $PID_STATUS 2>/dev/null; echo '[collect_metrics] Collecte arrêtée.'" EXIT
wait
