# AGENTS

Invariantes del proyecto. Detalle en los archivos citados, no aquí.

## App
- Cambio funcional o visual → bump `AppVersion.current` (footer de Ajustes).
- UI: solo `DESIGN.md`. Si falta, pregunta; no inventes.
- No uses `xcodebuild`.
- Commit solo si el usuario lo pide. Si pide commit, haz también `git push`.

## Subagentes
Definidos en `.cursor/agents/`. Delegar por especialidad; no para ediciones triviales.
- Trabajo mediano/grande o varias especialidades → `orchestrator`.
- Cerca del límite: para y devuelve encontrado / pendiente / siguiente paso.

## CodeGraph
`.codegraph/` está indexado. `codegraph_explore` es token-heavy: no lo llames en la sesión principal. Lanza un agente Explore y dile que lo use como herramienta primaria y no re-lea el source que ya devolvió.
