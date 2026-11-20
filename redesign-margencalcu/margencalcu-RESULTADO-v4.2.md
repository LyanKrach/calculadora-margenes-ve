# MargenCalcu v4.2 — vacío vertical lleno y etiquetas de tasa completas

Fecha: 2026-11-20
Base: commit `1f041b2` (v4.1). No se revirtió v4 ni v4.1.
Commit de código: `a6d9dd2` — `fix: llenar vacío vertical y etiquetas de tasa completas`.

## Qué cambió

### 1. Vacío vertical
- El body sigue sin scroll (`LayoutBuilder` + `Column`, sin `SingleChildScrollView`, `ListView` ni `ScrollPhysics` vertical).
- Se eliminó el `Spacer` único que volcaba todo el sobrante sobre el CTA. Las tres secciones ahora son `Expanded` con flex `5:5:7` (el selector de tasa sube a `6` cuando aparece la tasa personalizada o el aviso de tasas), de modo que el espacio se reparte entre tasa, margen/comisiones y redondeo.
- Los contenedores usan `MainAxisAlignment.spaceBetween` para crecer por dentro en vez de dejar un hueco negro.
- Modo teléfono alto (>= 650 px lógicos): tarjetas de tasa de **76 px**, inputs de **54 px**, padding interno de **16 px**, chips de **34 px**, segmentos de **36 px**, CTA de **52 px** y padding exterior de **14 px**.
- Los tamaños siguen siendo responsivos: `ultraTight < 470 px`, `tight < 560 px` y modo medio para el resto; a 360x640 no hay overflow.
- El botón “Calcular precio” queda fijo abajo y el hueco sobre él es de **10 px** (el gap normal entre secciones), no un `Spacer` gigante.

### 2. Etiquetas de tasa completas
- La tarjeta de tasa se reestructuró: icono pequeño arriba (14 px), badge “Hoy” y check de seleccionada en la misma fila, y debajo la etiqueta + valor apilados a todo el ancho.
- La etiqueta ya no compite con el icono por el ancho y usa `FittedBox(scaleDown)` con `maxLines: 1` y sin elipsis. A 360 px se leen completas **“Binance USDT”** y **“Personalizada”**.
- Se conservan el badge “Hoy”, el check de selección y la tarjeta activa en verde.

### 3. Versión
- `pubspec.yaml`: `1.1.2+5`.
- Pantalla de ajustes: texto de versión actualizado a `1.1.2+5`.

## Verificación

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | **0 issues** (`No issues found!`) |
| `flutter test` | **62/62 en verde** (60 existentes + 2 nuevos) |
| Tests nuevos | `test/calculator_v42_fill_test.dart`: a **360x800** y **360x880** sin overflow, sin scroll vertical/horizontal, CTA visible, etiquetas completas dentro de la tarjeta, tarjetas de 72–80 px, inputs >= 54 px y hueco sobre el CTA <= 24 px |
| `flutter build apk --release` | **OK**: `build/app/outputs/flutter-apk/app-release.apk` (56.3 MB) |
| Play Console | **No se subió nada** (ni interna, cerrada ni producción) |
| `git push origin main` | **OK**: `1f041b2..a6d9dd2` |

## Alcance respetado
- Solo UI de la Calculadora + versión. No se tocaron fórmulas, `rates_service`, modelos, auth, Firebase, Pro, paquete ni textos en español.
- No se agregaron dependencias.
- Diff revisado antes del push: sin `AIza`, claves privadas ni secretos.
