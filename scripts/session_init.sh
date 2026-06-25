
#!/usr/bin/env bash
# Initialise une session QA : vérifie ADB, crée les dossiers, lance l'app, mesure le startup.
# Usage : ./session_init.sh <APP_PACKAGE>
# Retour : exporte SESSION_ID et écrit output/<SESSION_ID>/session.json

set -euo pipefail

APP_PACKAGE="${1:?Usage: $0 <APP_PACKAGE>}"

# ── 1. Vérifier ADB ──────────────────────────────────────────────────────────
echo "[session_init] Vérification ADB..."
DEVICE=$(adb devices | awk 'NR==2 && $2=="device" {print $1}')
if [ -z "$DEVICE" ]; then
    echo "[ERREUR] Aucun appareil ADB connecté. Vérifiez le câble USB et le mode développeur." >&2
    exit 1
fi
echo "[session_init] Appareil détecté : $DEVICE"

# ── 2. Vérifier que l'app est installée ──────────────────────────────────────
if ! adb shell pm list packages | grep -q "^package:${APP_PACKAGE}$"; then
    echo "[ERREUR] Package '$APP_PACKAGE' non trouvé sur le casque." >&2
    exit 1
fi

# ── 3. Créer la structure de dossiers ────────────────────────────────────────
SESSION_ID="session_$(date +%Y%m%d_%H%M%S)"
SESSION_DIR="output/${SESSION_ID}"
mkdir -p "${SESSION_DIR}"/{screenshots,logs,metrics,agent_status}
echo "[session_init] Session créée : ${SESSION_DIR}"

# ── 4. Écrire session.json ────────────────────────────────────────────────────
cat > "${SESSION_DIR}/session.json" << EOF
{
  "session_id": "${SESSION_ID}",
  "package": "${APP_PACKAGE}",
  "device": "${DEVICE}",
  "start_time": "$(date +%H:%M:%S)",
  "start_date": "$(date +%Y-%m-%d)",
  "status": "running",
  "agents_active": []
}
EOF

# ── 5. Initialiser la file d'alertes ─────────────────────────────────────────
touch "${SESSION_DIR}/alerts.queue"

# ── 6. Lancer l'app et mesurer le startup ────────────────────────────────────
echo "[session_init] Lancement de l'app..."
adb logcat -c  # vider le logcat avant le démarrage

adb shell monkey -p "${APP_PACKAGE}" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1

# Attendre le message "Displayed" dans logcat (timeout 15s)
START_MS=$(date +%s%3N)
STARTUP_TIME=""
TIMEOUT=15

for i in $(seq 1 $((TIMEOUT * 10))); do
    DISPLAYED=$(adb logcat -d | grep "Displayed.*${APP_PACKAGE}" | tail -1)
    if [ -n "$DISPLAYED" ]; then
        END_MS=$(date +%s%3N)
        STARTUP_TIME=$(( END_MS - START_MS ))
        break
    fi
    sleep 0.1
done

if [ -n "$STARTUP_TIME" ]; then
    echo "[session_init] Startup mesuré : ${STARTUP_TIME} ms"
    echo "${STARTUP_TIME}" > "${SESSION_DIR}/metrics/startup_time.txt"
    if [ "$STARTUP_TIME" -gt 10000 ]; then
        echo "[$(date +%H:%M:%S)][session_init][CRITICAL] Startup=${STARTUP_TIME}ms — seuil critique (>10s) dépassé" >> "${SESSION_DIR}/alerts.queue"
    elif [ "$STARTUP_TIME" -gt 5000 ]; then
        echo "[$(date +%H:%M:%S)][session_init][WARNING] Startup=${STARTUP_TIME}ms — seuil alerte (>5s) dépassé" >> "${SESSION_DIR}/alerts.queue"
    fi
else
    echo "[session_init] Startup non mesuré (timeout ${TIMEOUT}s)"
    echo "non_mesuré" > "${SESSION_DIR}/metrics/startup_time.txt"
fi

# ── 7. Exporter SESSION_ID pour les scripts appelants ────────────────────────
echo "${SESSION_ID}" > /tmp/qa_current_session
echo "[session_init] ✅ Session initialisée : ${SESSION_ID}"
echo "export SESSION_ID=${SESSION_ID}"
