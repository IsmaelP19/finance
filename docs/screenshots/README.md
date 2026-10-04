# Screenshots

Este directorio contiene las capturas usadas en la documentación y en la ficha de SideStore.

## Galería actual

- `home.png`: Inicio, con cuentas y resumen financiero.
- `movements.png`: lista de movimientos cotidianos.
- `investments.png`: evolución de la cartera de inversiones.
- `wrapped-september.png`: resumen mensual Wrapped de septiembre.
- Capturadas el 4 de octubre de 2026 en el simulador iPhone 16 Pro Max (iOS 27).
- Resolución: 1320 × 2868 píxeles.
- Todos los datos son inventados, con nombres, movimientos e importes verosímiles para mostrar un uso normal de la app. No proceden de cuentas ni operaciones personales.
- El README principal muestra esta galería. El workflow de SideStore copia los cuatro archivos a `screenshots/` en GitHub Pages; la fuente referencia sus URL, ancho y alto en el mismo orden.

## Actualizarla

1. Preparar un simulador de demostración con datos completamente inventados y abrir cada una de las cuatro vistas. Revisar que no aparezcan datos personales, notificaciones ni información ajena a la app.
2. Capturar las vistas y sustituir los PNG conservando sus nombres. Actualizar la fecha, el dispositivo y los textos de las vistas indicados aquí y en el README principal.
3. Comprobar la resolución de los cuatro archivos. Si cambia, actualizar `width` y `height` en `scripts/update_sidestore_source.py`. Si se añaden o renombran capturas, actualizar también `SCREENSHOT_FILES`, la lista del workflow y la galería del README.
4. Revisar visualmente los PNG y generar una fuente de prueba local para comprobar las URL, dimensiones y orden de las capturas.
5. Publicar mediante el flujo habitual de `release/*`. El despliegue de Pages publica las imágenes junto con la fuente; comprobar sus URL y actualizar las fuentes en SideStore para ver la galería.

Las capturas son referencias visuales; no garantizan que todos los dispositivos o versiones de iOS se vean exactamente igual.
