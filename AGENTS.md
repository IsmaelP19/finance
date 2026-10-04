# AGENTS

Reglas del proyecto. La coordinación y la revisión final corresponden al agente principal.

## App

- Cambio funcional o visual → actualizar `AppVersion.current` (footer de Ajustes).
- UI: seguir `DESIGN.md`. Si falta, preguntar; no inventar un sistema visual.
- No usar `xcodebuild`.
- Commit solo si el usuario lo pide. Si pide commit, hacer también `git push`.

## Delegación

- Delegar por especialidad cuando reduzca riesgo o contexto; resolver directamente tareas triviales y ediciones mecánicas. No añadir un subagente solo para decidir qué subagente usar.
- Pregunta concreta sobre código → `explorer` de Codex o `Explore` integrado de Cursor; requisito ambiguo o cambio transversal → `planner` antes de editar; implementación acotada → `implementer`; UI/UX → `frontend-designer`; fallo o regresión → `debugger`; revisión independiente de un cambio significativo → `code-reviewer`.
- Elegir modelo y esfuerzo **por dificultad del encargo**, sin heredar por inercia el modelo principal: modelo ligero con esfuerzo bajo para búsqueda concreta; ligero con esfuerzo medio para cambios delimitados; intermedio con esfuerzo medio/alto para varios módulos, diagnóstico o revisión exigente; modelo de frontera solo si persiste una ambigüedad o un riesgo excepcional. Ejemplos, cuando estén disponibles: Luna → Sol → Astra. Respetar el esfuerzo fijo de un rol y comprobar que el modelo elegido lo admite.
- En Codex usar los roles y parámetros de delegación disponibles; en Cursor, `.cursor/agents/` aporta perfiles base que pueden ajustarse al lanzar cada tarea. Si un modelo no está disponible, usar otro de capacidad comparable y comunicar la limitación si afecta al resultado.
- Enviar un encargo breve con objetivo, archivos o área, límites, evidencia esperada y validación. En ediciones paralelas, asignar archivos distintos. No duplicar exploraciones ni pasar toda la conversación; el agente principal verifica hallazgos, diff y pruebas antes de cerrar.
- Si el contexto se agota, resumir lo encontrado, lo pendiente y el siguiente paso para continuar sin repetir búsquedas.

## CodeGraph

`.codegraph/` ya está indexado. Para descubrir código, priorizar consultas de grafo enfocadas. Reservar `codegraph_explore`, que consume mucho contexto, al `explorer` de Codex o `Explore` integrado de Cursor; pedirle que no vuelva a leer el código que la herramienta ya devolvió. Usar `rg` para literales, configuración, documentación o cuando el grafo no baste. No reconstruir el índice sin autorización.
