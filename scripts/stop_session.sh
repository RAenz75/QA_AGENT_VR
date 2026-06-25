#!/usr/bin/env bash
# Arrête proprement une session QA : kill les processus background, pull les artefacts, nettoie le /sdcard.
# Usage : ./stop_session.sh <SESSION_ID> <APP_PACKAGE>

set -euo pipefail

SESSION_ID="${1:?Usage: $0 <SESSION_ID> <APP_PACKAGE>}"
APP_PACKAGE="${2:?Usage: $0 <SESSION_ID> <APP_PACKAGE>}"
SESSION_DIR="output/${SESSION_ID}"

if [ ! -d "$SESSION_DIR" ]; then
    echo "[ERREUR] Dossier de session introuvable : ${SESSION_DIR}" >&2
    exit 1
fi

echo "[stop_session] Arrêt de la session ${SESSION_ID}..."

# ── 1. Arrêter les processus background ──────────────────────────────────────
_kill_pids() {
    local pid_file="$1"
    local label="$2"
    if [ -f "$pid_file" ]; then
        local pids; pids=$(cat "$pid_file")
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null && echo "[stop_session] Arrêté : ${label} (PID ${pid})"
            fi
        done
        rm -f "$pid_file"
    fi
}

_kill_pids "${SESSION_DIR}/metrics/collector.pid" "collect_metrics"
_kill_pids "${SESSION_DIR}/logs/watcher.pid" "watch_stability"

# ── 2. Fermer l'app ───────────────────────────────────────────────────────────
echo "[stop_session] Fermeture de l'app..."
adb shell am force-stop "$APP_PACKAGE" 2>/dev/null || true

# ── 3. Pull des artefacts depuis le casque ───────────────────────────────────
echo "[stop_session] Récupération des artefacts depuis le casque..."
adb pull "/sdcard/QA_temp/" "${SESSION_DIR}/" 2>/dev/null || true

# Screenshots laissés sur le /sdcard par les scripts (crash, ANR...)
for file in $(adb shell ls /sdcard/*.png 2>/dev/null | tr -d '\r' || true); do
    adb pull "$file" "${SESSION_DIR}/screenshots/" 2>/dev/null || true
    adb shell rm "$file" 2>/dev/null || true
done

# ── 4. Nettoyer le /sdcard ───────────────────────────────────────────────────
echo "[stop_session] Nettoyage du /sdcard..."
adb shell rm -rf /sdcard/QA_temp/ 2>/dev/null || true
adb shell rm -f /sdcard/ui_dump*.xml /sdcard/screen*.png 2>/dev/null || true

# ── 5. Mettre à jour session.json ────────────────────────────────────────────
SESSION_JSON="${SESSION_DIR}/session.json"
if [ -f "$SESSION_JSON" ]; then
    # Remplacer "running" par "done" et ajouter end_time
    sed -i '' 's/"status": "running"/"status": "done"/' "$SESSION_JSON" 2>/dev/null || \
    sed -i 's/"status": "running"/"status": "done"/' "$SESSION_JSON"
    echo "[stop_session] session.json mis à jour."
fi

# ── 6. Résumé des artefacts ──────────────────────────────────────────────────
echo ""
echo "=== Session ${SESSION_ID} terminée ==="
echo "Artefacts disponibles dans : ${SESSION_DIR}/"
echo ""
echo "  Screenshots : $(find "${SESSION_DIR}/screenshots" -name '*.png' 2>/dev/null | wc -l | tr -d ' ') fichiers"
echo "  Logs        : $(find "${SESSION_DIR}/logs" -type f 2>/dev/null | wc -l | tr -d ' ') fichiers"
echo "  Métriques   : $(find "${SESSION_DIR}/metrics" -type f 2>/dev/null | wc -l | tr -d ' ') fichiers"
echo ""
echo "Prochaine étape : invoquer l'agent report-writer avec :"
echo "  Session ID : ${SESSION_ID}"
echo "  Package    : ${APP_PACKAGE}"
echo "  Chemin     : ${SESSION_DIR}/"
