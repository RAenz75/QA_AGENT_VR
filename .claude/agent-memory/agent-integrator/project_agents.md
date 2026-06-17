---
name: project-agents
description: Ecosystème des 5 agents QA du projet Pico3 — rôles, tools, dépendances et artefacts
metadata:
  type: project
---

Emplacement des agents : `/Users/enzo/Documents/DEV/QA/.claude/agents/`

## Agents QA intégrés

| name | fichier | tools | rôle |
|------|---------|-------|------|
| qa-orchestrator | qa-orchestrator.md | Bash, Read, Write, Agent | Chef d'orchestre — point d'entrée unique pour démarrer une session QA |
| ui-explorer | ui-explorer.md | Bash, Read, Write | Exploration UI via UIAutomator2 + ADB, génération et exécution de cas de test |
| perf-monitor | perf-monitor.md | Bash, Read, Write | Collecte FPS/mémoire/CPU/température, alertes seuils, CSV |
| stability-watcher | stability-watcher.md | Bash, Read, Write | Surveillance logcat, détection crashes/ANR/OOM |
| report-writer | report-writer.md | Bash, Read, Write | Consolidation artefacts + rapport QA final avec score pondéré |

## Dépendances d'artefacts (producteur → consommateur)

- `ui-explorer` → produit `output/$SESSION_ID/test_cases.md` → consommé par `report-writer`
- `perf-monitor` → produit `metrics/fps_data.csv`, `metrics/memory_data.csv`, `metrics/perf_summary.md` → consommés par `report-writer`
- `stability-watcher` → produit `logs/incidents.log`, `logs/stability_summary.md` → consommés par `report-writer` et `qa-orchestrator` (poll toutes les 10 min)
- `perf-monitor` → écrit dans `metrics/alerts.log` → lu par `qa-orchestrator`
- Tous les agents → produisent des screenshots dans `screenshots/` → consommés par `report-writer`

## Canal de communication inter-agents

Les agents spécialisés communiquent avec `qa-orchestrator` via :
1. Les fichiers partagés (`incidents.log`, `alerts.log`) — communication asynchrone
2. Le retour de résultat de l'appel Agent (communication synchrone directe)

## Convention de nommage SESSION_ID

`session_YYYYMMDD_HHMMSS` — créé par `qa-orchestrator` au démarrage, partagé avec tous les agents dans le prompt de délégation.

**Why:** Convention définie dans CLAUDE.md, cohérente dans tous les agents.
**How to apply:** Toujours vérifier que SESSION_ID est transmis dans le prompt de délégation.
