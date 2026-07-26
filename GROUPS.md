# Grupos

Este documento recoge el alcance funcional y las decisiones de producto definidas para la futura funcionalidad **Grupos**.

La funcionalidad se prioriza por encima de la detección de tickets/OCR.

## Objetivo

La sección **Grupos** permitirá gestionar gastos compartidos de viajes, planes o grupos durante varios días, de forma similar a Tricount.

El objetivo principal es:

- Registrar gastos pagados por distintas personas.
- Repartir gastos entre participantes.
- Calcular el balance neto del grupo.
- Minimizar el número de pagos necesarios para saldar cuentas.

## Enfoque inicial

La primera implementación será **solo local**.

Queda fuera inicialmente:

- Sincronización entre dispositivos.
- CloudKit compartido.
- Backend propio.
- Colaboración en tiempo real.
- Android.
- Invitaciones o enlaces compartidos.
- OCR/detección de tickets.

La app podrá funcionar como un gestor local de grupos: una persona crea y mantiene el grupo desde su dispositivo, añadiendo participantes aunque no tengan la app instalada.

La sincronización se reconsiderará más adelante, especialmente si se desarrolla una versión Android.

## Concepto principal

Se separan dos mundos:

```text
Movimientos = caja real / patrimonio
Grupos      = reparto, balance y deudas
```

Los **Movimientos** reflejan entradas y salidas reales de las cuentas del usuario.

Los **Grupos** reflejan quién ha pagado, quién participa en cada gasto, cómo se reparte y qué balance final tiene cada participante.

## Participantes

Inicialmente, los participantes serán nombres dentro del grupo.

Ejemplo:

```text
Yo
Ana
Luis
Marta
```

No necesitan registro, cuenta ni tener la aplicación instalada.

El usuario podrá registrar gastos pagados por cualquiera de los participantes.

## Gastos de grupo

Cada gasto de grupo deberá permitir definir:

- Concepto.
- Importe.
- Fecha.
- Pagador.
- Participantes incluidos en el gasto.
- Reparto.
- Relación opcional con un Movimiento local.

El pagador puede ser el usuario local o cualquier otro participante.

## Tipos de reparto

El reparto no será exclusivamente igualitario.

Se contemplan al menos dos tipos:

1. **Reparto igualitario** entre los participantes seleccionados.
2. **Reparto por importe personalizado**, especificando cuánto corresponde a cada persona.

En reparto personalizado, la suma de importes deberá coincidir con el total del gasto.

## Integración con Movimientos

Cada gasto del grupo podrá ofrecer la opción:

```text
Incluir en Movimientos
```

Pero esta opción solo debe aparecer cuando:

```text
Pagador == Yo
```

Si el pagador es otra persona, el gasto solo afecta al balance del grupo y no crea ningún Movimiento en las cuentas del usuario.

Si el pagador es el usuario local y decide incluirlo en Movimientos:

- Se elige cuenta.
- Se elige categoría.
- Se crea un Movimiento real por el importe completo.
- El Movimiento queda vinculado al gasto de grupo.

Ejemplo:

```text
Gasto de grupo:
Hotel Roma — 600 €
Pagado por mí
Dividido entre 3 personas
Mi parte: 200 €

Movimiento creado:
Hotel Roma — -600 €
Cuenta: Banco
Vinculado al gasto de grupo
```

La razón de registrar el Movimiento completo es que representa la salida real de caja/patrimonio.

## Regla clave sobre reembolsos

Un Movimiento vinculado a un gasto de Grupo **nunca genera reembolso esperado propio**.

El reembolso o pago pendiente nace exclusivamente del **balance neto del Grupo**.

Esto evita duplicidades o reembolsos incorrectos cuando varios participantes pagan distintos gastos que se compensan entre sí.

Ejemplo:

```text
Yo pago hotel: 600 €
Ana paga vuelos: 600 €
Luis paga comidas: 600 €
Todo se divide entre los 3

Balance final del grupo: 0 €
Reembolsos pendientes: ninguno
```

Aunque mi Movimiento de hotel sea de -600 €, no debe generar un reembolso esperado individual de 400 €, porque el balance del grupo ya queda compensado.

## Balance del grupo

El grupo será la fuente de verdad para calcular:

- Total pagado por cada participante.
- Total que corresponde a cada participante.
- Balance neto de cada participante.
- Quién debe a quién.
- Pagos sugeridos minimizados.

Ejemplo:

```text
Ana paga 90 €
Luis paga 0 €
Marta paga 0 €
Reparto igualitario entre 3

Ana: +60 €
Luis: -30 €
Marta: -30 €

Pagos sugeridos:
Luis -> Ana: 30 €
Marta -> Ana: 30 €
```

## Reembolsos / futura vista Balance

La vista actual de reembolsos esperados se adaptará para soportar dos tipos de origen:

1. **Movimiento individual**.
2. **Grupo**.

Ejemplo de Movimiento individual:

```text
Cena viernes
Te deben 50 €
Origen: Movimiento
```

Ejemplo de Grupo:

```text
Viaje Roma
Te deben 60 €
Origen: Grupo
```

Para Grupos, la vista será agregada y simple. No mostrará el detalle de cada gasto ni de cada persona en esa pantalla.

Al pulsar sobre el Grupo, se abrirá el detalle del grupo, donde sí se podrán ver:

- Gastos.
- Participantes.
- Balance.
- Pagos sugeridos.
- Detalle de quién debe a quién.

Regla crítica:

```text
Un Movimiento vinculado a Grupo no aparece como reembolso individual.
```

## Liquidaciones

Más adelante, los Grupos deberán permitir registrar liquidaciones.

Ejemplo:

```text
Ana me paga 20 €
Luis me paga 40 €
```

Estas liquidaciones actualizan el balance del grupo.

Si una liquidación afecta a las cuentas del usuario local, se podrá crear un Movimiento real opcional:

- Si me pagan: ingreso.
- Si pago yo: salida.

## Edición y borrado en modo local

Como la primera versión será local, no habrá conflictos entre dispositivos.

Si se borra un gasto pagado por el usuario y con Movimiento vinculado, la app deberá preguntar qué hacer:

- Borrar gasto y Movimiento.
- Borrar solo el gasto y conservar el Movimiento.
- Cancelar.

Si se edita un gasto con Movimiento vinculado, se deberá valorar si se actualiza también el Movimiento vinculado.

## Estadísticas personales

Debe distinguirse entre:

- Importe real del Movimiento.
- Parte imputada al usuario dentro del Grupo.

Ejemplo:

```text
Hotel — 600 €
Pagado por mí
Dividido entre 3
Mi parte: 200 €
```

Para caja/patrimonio:

```text
Cuenta bancaria: -600 €
```

Para gasto personal imputado:

```text
Viajes / Hotel: 200 €
```

A largo plazo, las estadísticas personales deberían poder considerar:

- Movimientos normales.
- Mi parte imputada en gastos de Grupos.

Esto permitiría reflejar gastos personales aunque otro participante haya pagado inicialmente.

## Tickets/OCR

La detección de tickets queda pospuesta.

Más adelante podría usarse dentro de Grupos para:

- Escanear tickets.
- Detectar líneas/productos.
- Asignar productos a participantes.
- Repartir por línea.
- Crear gastos de grupo.
- Crear Movimiento si el usuario local fue quien pagó.

## Sincronización futura

La sincronización queda fuera del alcance inicial.

Si en el futuro se desarrolla Android, se valorará un backend propio o una solución multiplataforma.

La arquitectura futura recomendada sería:

```text
local-first + sincronización + backend para agregados
```

No se recomienda una app totalmente dependiente del backend.

El backend podría calcular:

- Estadísticas agregadas.
- Balances de grupos.
- Reembolsos/pagos pendientes.
- Resúmenes para dashboard.

Pero la app debería conservar datos locales y poder funcionar al menos parcialmente offline.

## MVP recomendado

Primera versión de Grupos:

- Nueva sección **Grupos**.
- Grupos locales.
- Participantes por nombre.
- Gastos manuales.
- Pagador seleccionable.
- Reparto igualitario.
- Reparto por importes personalizados.
- Balance neto del grupo.
- Pagos sugeridos minimizados.
- Opción **Incluir en Movimientos** solo si el pagador es el usuario local.
- Movimiento vinculado por importe completo.
- Los Movimientos vinculados a Grupo no generan reembolso propio.
- Vista de reembolsos adaptada para mostrar Grupos como origen agregado.

## Pendientes de definir antes de implementar

- Cómo se identificará exactamente el participante local **Yo** dentro de cada grupo.
- Si un grupo tendrá estado `abierto`, `cerrado` o `liquidado`.
- Cómo se actualizará un Movimiento vinculado cuando se edite el gasto de grupo.
- Qué nivel de integración tendrán las estadísticas personales en la primera versión.
- Cómo se representarán las liquidaciones en el modelo de datos.
