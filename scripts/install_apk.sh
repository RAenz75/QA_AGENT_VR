#!/usr/bin/env bash
# Installe une APK sur le casque Pico3 via ADB avec vérification complète.
# Usage : ./install_apk.sh <APK_FILE_PATH> [APP_PACKAGE]
# APP_PACKAGE est optionnel si aapt est disponible pour le détecter automatiquement.

set -euo pipefail

APK_FILE_PATH="${1:?Usage: $0 <APK_FILE_PATH> [APP_PACKAGE]}"
APP_PACKAGE="${2:-}"

# ── 1. Vérifier ADB ──────────────────────────────────────────────────────────
echo "[install_apk] Vérification ADB..."
DEVICE=$(adb devices | awk 'NR==2 && $2=="device" {print $1}')
if [ -z "$DEVICE" ]; then
    echo "[ERREUR] Aucun appareil ADB connecté. Vérifiez le câble USB et le mode développeur." >&2
    exit 1
fi
echo "[install_apk] Appareil : ${DEVICE}"

# ── 2. Vérifier que le fichier APK existe ────────────────────────────────────
if [ ! -f "$APK_FILE_PATH" ]; then
    echo "[ERREUR] Fichier APK introuvable : ${APK_FILE_PATH}" >&2
    echo ""
    echo "APK disponibles :"
    ls -lh /APK/TEST/ 2>/dev/null && echo "--- TEST ---" || true
    ls -lh /APK/PROD/ 2>/dev/null && echo "--- PROD ---" || true
    exit 1
fi

APK_SIZE=$(du -h "$APK_FILE_PATH" | cut -f1)
echo "[install_apk] APK : ${APK_FILE_PATH} (${APK_SIZE})"

# ── 3. Détecter le package si non fourni ─────────────────────────────────────
if [ -z "$APP_PACKAGE" ]; then
    if command -v aapt &>/dev/null; then
        APP_PACKAGE=$(aapt dump badging "$APK_FILE_PATH" 2>/dev/null | grep "package: name=" | sed "s/.*name='\([^']*\)'.*/\1/")
        echo "[install_apk] Package détecté : ${APP_PACKAGE}"
    else
        echo "[ERREUR] aapt non disponible et APP_PACKAGE non fourni." >&2
        echo "Usage : $0 <APK_FILE_PATH> <APP_PACKAGE>" >&2
        exit 1
    fi
fi

# ── 4. Version actuellement installée ────────────────────────────────────────
VERSION_BEFORE=$(adb shell dumpsys package "$APP_PACKAGE" 2>/dev/null | grep "versionName" | head -1 | tr -d ' ' | cut -d'=' -f2 || echo "non installé")
echo "[install_apk] Version actuelle : ${VERSION_BEFORE}"

# ── 5. Arrêter l'app avant installation ──────────────────────────────────────
echo "[install_apk] Arrêt de l'app..."
adb shell am force-stop "$APP_PACKAGE" 2>/dev/null || true
sleep 1

# ── 6. Installer ─────────────────────────────────────────────────────────────
echo "[install_apk] Installation en cours..."
INSTALL_OUTPUT=$(adb install -r -d "$APK_FILE_PATH" 2>&1)

if echo "$INSTALL_OUTPUT" | grep -q "^Success"; then
    echo "[install_apk] Installation réussie."
elif echo "$INSTALL_OUTPUT" | grep -q "INSTALL_FAILED_VERSION_DOWNGRADE"; then
    echo "[install_apk] Version inférieure détectée — nouvelle tentative sans -d..."
    INSTALL_OUTPUT=$(adb install -r "$APK_FILE_PATH" 2>&1)
    if ! echo "$INSTALL_OUTPUT" | grep -q "^Success"; then
        echo "[ERREUR] Échec de l'installation : ${INSTALL_OUTPUT}" >&2
        exit 1
    fi
    echo "[install_apk] Installation réussie (upgrade)."
elif echo "$INSTALL_OUTPUT" | grep -q "INSTALL_FAILED_INSUFFICIENT_STORAGE"; then
    echo "[ERREUR] Espace disque insuffisant sur le casque." >&2
    echo "Espace disponible :" >&2
    adb shell df /sdcard >&2
    exit 1
else
    echo "[ERREUR] Échec de l'installation :" >&2
    echo "$INSTALL_OUTPUT" >&2
    exit 1
fi

# ── 7. Vérifier l'installation ───────────────────────────────────────────────
echo "[install_apk] Vérification post-installation..."
if ! adb shell pm list packages | grep -q "^package:${APP_PACKAGE}$"; then
    echo "[ERREUR] Package '${APP_PACKAGE}' introuvable après installation — échec silencieux." >&2
    exit 1
fi

VERSION_AFTER=$(adb shell dumpsys package "$APP_PACKAGE" 2>/dev/null | grep "versionName" | head -1 | tr -d ' ' | cut -d'=' -f2 || echo "inconnu")

# ── 8. Résumé ─────────────────────────────────────────────────────────────────
echo ""
echo "✅ Installation réussie"
echo "   Package  : ${APP_PACKAGE}"
echo "   Version  : ${VERSION_BEFORE} → ${VERSION_AFTER}"
echo "   Fichier  : ${APK_FILE_PATH} (${APK_SIZE})"
echo "   Appareil : ${DEVICE}"
echo ""

# Proposer de lancer l'app
read -r -p "Lancer l'app maintenant ? [o/N] " LAUNCH
if [[ "$LAUNCH" =~ ^[oO]$ ]]; then
    adb shell monkey -p "$APP_PACKAGE" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    echo "[install_apk] App lancée."
fi
