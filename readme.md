# QA Automatisé — Pico3

Système de tests QA **black-box** piloté par agents Claude Code pour une APK Android sur casque **Pico3** (AOSP). Connexion via ADB USB, aucune modification de l'APK requise.

---

## Prérequis

- ADB installé et accessible dans le PATH
- Casque Pico3 connecté en USB avec le **mode développeur activé**
- `aapt` installé (optionnel — sert à détecter le package depuis l'APK automatiquement)
- Claude Code CLI

---

## Démarrage rapide

### 1. Installer une nouvelle APK

```bash
./scripts/install_apk.sh /APK/TEST/monapp_v1.2.apk com.example.app
```

### 2. Lancer une session QA complète

Invoquer l'agent orchestrateur dans Claude Code :

```
Lance une session QA standard sur com.example.app
```

L'orchestrateur (`qa-orchestrator`) prend en charge le reste : il initialise la session, délègue aux agents spécialisés et génère le rapport final.

---

## Architecture

```
.claude/agents/
├── qa-orchestrator.md      # Chef d'orchestre — pilote la session de bout en bout
├── ui-explorer.md          # Exploration UI + génération et exécution de cas de test
├── perf-monitor.md         # Métriques FPS, mémoire, CPU (s'appuie sur collect_metrics.sh)
├── stability-watcher.md    # Crashes, ANR, OOM (s'appuie sur watch_stability.sh)
├── report-writer.md        # Synthèse et rapport QA final
└── version_updater.md      # Mise à jour de l'APK sur le casque

scripts/
├── session_init.sh          # Vérifie ADB, crée les dossiers, lance l'app, mesure le startup
├── collect_metrics.sh       # Boucles FPS + mémoire + CPU en background
├── watch_stability.sh       # Logcat en background — détection crash/ANR/OOM
├── stop_session.sh          # Arrêt propre, pull artefacts, nettoyage /sdcard
└── install_apk.sh           # Installation APK avec vérification pré/post

output/
└── session_YYYYMMDD_HHMMSS/
    ├── screenshots/          # Captures PNG horodatées
    ├── logs/                 # Logcat brut, filtré, incidents
    ├── metrics/              # CSV FPS / mémoire / CPU
    ├── agent_status/         # Statut JSON de chaque agent (lu par l'orchestrateur)
    ├── alerts.queue          # File d'alertes inter-agents
    ├── session.json          # Métadonnées de session
    └── report.md             # Rapport final généré par report-writer

APK/
├── TEST/                     # Builds de test / staging
└── PROD/                     # Builds de production
```

---

## Scripts

| Script | Usage | Rôle |
|---|---|---|
| `session_init.sh` | `<PKG>` | Vérifie ADB, crée `output/session_YYYYMMDD_HHMMSS/`, lance l'app, mesure le startup, exporte `$SESSION_ID` |
| `collect_metrics.sh` | `<PKG> <SESSION_ID>` | 3 boucles background (FPS/10s, mémoire/30s, CPU/10s), écrit les CSV + `agent_status/perf-monitor.json` + `alerts.queue` |
| `watch_stability.sh` | `<PKG> <SESSION_ID>` | Logcat en background, détecte crash/ANR/OOM, écrit `agent_status/stability-watcher.json` + `alerts.queue` + screenshots automatiques |
| `stop_session.sh` | `<SESSION_ID> <PKG>` | Kill tous les PIDs background, ferme l'app, pull les artefacts du casque, nettoie `/sdcard` |
| `install_apk.sh` | `<APK_PATH> [PKG]` | Vérifie APK, arrête l'app, installe, vérifie post-install, affiche version avant/après |

---

## Agents

### `qa-orchestrator`
Point d'entrée d'une session QA. Demande le package, la durée et les types de tests, puis orchestre les autres agents. Supervise la file `alerts.queue` toutes les 10 minutes.

**Sessions :**
- **Courte (< 30 min)** : ui-explorer + stability-watcher
- **Standard (30–90 min)** : ui-explorer + perf-monitor + stability-watcher
- **Longue (> 90 min)** : tous les agents, stress test mémoire inclus

### `ui-explorer`
Cartographie l'interface via UIAutomator2, génère les cas de test et les exécute. Se désactive automatiquement si l'app est en rendu VR natif (UIAutomator2 inefficace) et remonte l'information à l'orchestrateur.

### `perf-monitor`
Pilote `collect_metrics.sh` et surveille les seuils. Écrit son statut dans `agent_status/perf-monitor.json` et pousse les alertes dans `alerts.queue`.

### `stability-watcher`
Pilote `watch_stability.sh`. Détecte les crashes Java et natifs, ANR, OOM. Prend un screenshot automatique à chaque incident. Écrit son statut dans `agent_status/stability-watcher.json`.

### `report-writer`
Consolide tous les artefacts de session en un `report.md` avec score QA pondéré (Stabilité 40% / Performance 30% / UI 30%) et verdict `PASS` (≥ 70) ou `FAIL` (< 70).

### `version_updater`
Guide l'installation d'une nouvelle APK : liste les fichiers dans `/APK/TEST` et `/APK/PROD`, demande le choix, arrête l'app, installe, vérifie la version avant/après.

---

## Communication inter-agents

Les agents communiquent via des fichiers dans `output/$SESSION_ID/` — pas de socket, pas de réseau.

```
agent_status/<agent>.json   ← chaque agent écrit son statut (ok / warning / critical)
alerts.queue                ← append-only, l'orchestrateur lit et vide à chaque poll
```

Format des alertes dans `alerts.queue` :
```
[HH:MM:SS][agent][LEVEL] message
```

---

## Seuils de qualité

| Métrique | Alerte | Critique |
|---|---|---|
| FPS | < 60 fps | < 30 fps |
| Mémoire RSS | > 1.5 GB | > 2 GB |
| CPU app | > 60% | > 85% |
| Temps de démarrage | > 5s | > 10s |
| Crash | 1 occurrence | FAIL immédiat |

> Le Pico3 cible 72 Hz en mode confort. Un FPS moyen en dessous de 60 sur une session déclenche une alerte systématique.

---

## Format des cas de test

```
ID: TC-XXX
Titre: <description courte>
Préconditions: <état attendu avant le test>
Étapes: <liste numérotée>
Résultat attendu: <comportement correct>
Résultat observé: <à remplir à l'exécution>
Statut: PASS | FAIL | BLOCKED | SKIP
Preuves: <chemin screenshots / logs>
```
