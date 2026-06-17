---
name: project-integration-notes
description: Notes sur la première intégration des agents QA (2026-06-16) — problèmes trouvés et corrections
metadata:
  type: project
---

## Intégration du 2026-06-16

### Problèmes détectés et corrigés

1. **perf-monitor.md** : `perf_summary.md` listé dans les artefacts mais sans section de génération. Ajout d'une section "Synthèse en fin de session" avec le template du fichier.

2. **report-writer.md** : ordre des tools `Read, Write, Bash` — normalisé en `Bash, Read, Write` pour cohérence avec les autres agents.

3. **qa-orchestrator.md** : section délégation ne mentionnait pas l'usage explicite du tool `Agent` ni les noms valides des subagents. Précision ajoutée avec les valeurs valides de `subagent_type` et la note sur les appels parallèles.

4. **ui-explorer.md** : message de remontée vers `qa-orchestrator` en cas de rendu VR natif non formalisé. Ajout du message exact à retourner.

5. **stability-watcher.md** : doublon dans la ligne de log du crash (deux écritures dans incidents.log). Unifié et formaté avec préfixe `[CRASH][timestamp]`. Idem pour la surveillance processus mort.

6. **perf-monitor.md** : logique d'alerte sans format précis pour `alerts.log`. Ajout du format `[NIVEAU][METRIQUE][TIMESTAMP]` pour que `qa-orchestrator` puisse parser facilement.

### Ce qui était déjà correct

- Tous les `name:` sont uniques et en kebab-case
- Tous les frontmatters YAML sont valides (name, description, tools)
- Les références croisées dans `qa-orchestrator` correspondent exactement aux `name:` des agents
- Les chemins `output/$SESSION_ID/` sont cohérents entre tous les agents
- `qa-orchestrator` a bien le tool `Agent` pour déléguer

**Why:** Première intégration — agents bien conçus individuellement mais manquant de précision sur les contrats inter-agents.
**How to apply:** Lors de tout ajout d'agent, vérifier que ses artefacts de sortie correspondent aux attentes de `report-writer` et que ses canaux de remontée vers `qa-orchestrator` sont formalisés.
