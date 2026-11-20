# MargenCalcu v4.1 — Resultado

Base: commit `16c92c2` (rediseño v4).
Commit del fix: `2a2a023` — `fix: tasas compactas, las 4 visibles sin scroll horizontal`.
Versión: `1.1.1+4`.

## Qué cambió

- Selector de tasas: se reemplazó el `ListView.separated` horizontal por un `Row` con 4 `Expanded` (cada tarjeta 1/4 del ancho) y separación fija de 6 px. Sin scroll horizontal; las 4 tasas (BCV dólar, Binance USDT, Euro BCV y Personalizada) quedan visibles a 360 px.
- Tarjetas de tasa compactas: icono 20 px, etiqueta 11 px w800 en una línea con ellipsis, valor 10.5 px tabular dentro de `FittedBox` (no se recorta; "918,77 Bs/$" se lee completo), badge "Hoy" 9 px y check 13 px.
- Selección intacta: fondo verde al 16 % y borde 1.5 px en la tarjeta activa.
- Encabezado "Tasa del día": el resumen derecho pasó a `Expanded` con ellipsis para no desbordar a 360 px.
- Espacio vertical: se distribuyó el sobrante con `Spacer` entre las secciones (tasas, modo de margen, comisiones) y antes del CTA, en lugar de un único hueco sobre "Calcular precio". Se mantiene el body `Column` + `Spacer` + `LayoutBuilder` (tight/ultraTight), sin `SingleChildScrollView` ni scroll vertical.
- Altura de la fila de tasas ajustada a 62/64/68 px según modo para evitar overflow del contenido compacto.
- Sin cambios en fórmulas, tasas, modelos, auth, Firebase, Pro, paquete ni textos en español.

## Tests

- Nuevo `test/calculator_v41_rates_test.dart`:
  - Las 4 tarjetas caben en una fila a 360 px, con gap de 6 px y sin `ListView` horizontal.
  - La tasa personalizada "918,77 Bs/$" se muestra completa.
  - La Calculadora sigue sin scroll vertical y el botón "Calcular precio" queda visible a 360×640.
- `test/calculator_v4_redesign_test.dart` actualizado a la fila de 4 tarjetas (sin carrusel horizontal).

## Verificación

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | 0 issues (`No issues found!`) |
| `flutter test` | 60/60 en verde (58 existentes + 2 nuevos) |
| `flutter build apk --release` | OK — `build/app/outputs/flutter-apk/app-release.apk` (56.3 MB) |
| Escaneo de secretos en el diff (`AIza`, api keys, private keys) | Limpio |
| `git push origin main` | OK — `268ff50..2a2a023` |
| Play Console | No se subió nada (ni interna, ni cerrada, ni producción) |

El push incluye también el rediseño v4 (`16c92c2`), que aún no estaba en `origin/main` (el remoto estaba en `268ff50`).
