# CLAUDE.md — Projet QA Pico3

## Contexte

Ce projet est un système de QA automatisé en **black-box** pour une APK Android installée sur un casque **Pico3** (OS Android-based).

- **Connexion** : ADB USB (`adb devices` détecte le casque)
- **Accès** : APK installable, non modifiable (pas d'instrumentation, pas de sources)
- **Cible** : Tests UI, Performance, Stabilité
- **Framework retenu** : UIAutomator2 via `adb shell uiautomator` + `adb shell dumpsys` + logcat

## Architecture des agents

```
agents/
├── qa-orchestrator.md      # Chef d'orchestre — pilote la session de bout en bout
├── ui-explorer.md          # Exploration UI + génération et exécution de cas de test
├── perf-monitor.md         # Métriques FPS, latence, mémoire, CPU
├── stability-watcher.md    # Surveillance logs, crashes, ANR, exceptions
└── report-writer.md        # Synthèse et rapport QA final
```

## Conventions critiques

### Commandes ADB
- Toujours vérifier la connectivité avant toute commande : `adb devices`
- Package cible stocké dans la variable `$APP_PACKAGE` (à définir en début de session)
- Timeout standard pour les commandes shell : 30s
- En cas d'échec ADB, retenter 2 fois avant de signaler une erreur bloquante

### Fichiers de sortie
```
output/
├── session_YYYYMMDD_HHMMSS/
│   ├── screenshots/        # Captures PNG horodatées
│   ├── logs/               # Logcat brut + filtré
│   ├── metrics/            # CSV des métriques perf
│   └── report.md           # Rapport final généré par report-writer
```

### Format des cas de test
Chaque cas de test suit cette structure :
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

### Seuils de qualité (modifiables)
| Métrique         | Seuil d'alerte | Seuil critique |
|------------------|---------------|----------------|
| FPS              | < 60 fps      | < 30 fps       |
| Mémoire RSS      | > 1.5 GB      | > 2 GB         |
| CPU app          | > 60%         | > 85%          |
| Temps de démarrage | > 5s        | > 10s          |
| Crash            | 1 occurrence  | immédiat FAIL  |

## Démarrage d'une session QA

1. Lancer `qa-orchestrator` en lui fournissant :
   - Le nom du package APK (`$APP_PACKAGE`)
   - La durée cible de la session
   - Les types de tests à activer (UI / Perf / Stabilité)
2. L'orchestrateur délègue aux agents spécialisés en parallèle ou séquence selon le plan
3. En fin de session, `report-writer` consolide tous les artefacts

## Contraintes techniques Pico3

- **Résolution d'affichage** : 2160×2160 par œil (rendu VR — l'UI peut être en mode 2D pancake)
- **OS** : Android 10+ (AOSP modifié par Pico)
- **UIAutomator2** : Fonctionne uniquement si l'app est en mode **2D** (flatscreen dans le casque)
  - ⚠️ Pour les apps en rendu 3D/VR natif, l'exploration UI par UIAutomator2 sera **inefficace** — se replier sur logcat + perf uniquement
- **ADB screenshot** : `adb shell screencap -p /sdcard/screen.png && adb pull /sdcard/screen.png`

## Notes de rigueur

- Ne jamais supposer qu'une action UI a réussi sans vérification (screenshot ou dump XML post-action)
- Tout résultat de test **FAIL** doit être accompagné d'une preuve (log ou screenshot)
- Les métriques de performance doivent être collectées sur **minimum 60 secondes** pour être significatives
- Un seul crash = le cas de test est automatiquement **FAIL**, peu importe le reste