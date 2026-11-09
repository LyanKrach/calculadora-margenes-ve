# Calculadora de Márgenes VE — Flutter

Calculadora de márgenes para vendedores en Venezuela: costo en USD, tasa del día (BCV dólar, Binance USDT P2P, Euro BCV o personalizada), comisiones y margen deseado → precio de venta en bolívares sin perder dinero.

- App en español. Tema oscuro gamer sobrio (Material 3).
- Fórmula: **Precio en Bs = (Costo en Bs + Gasto fijo) ÷ (1 − comisiones − margen)**, con Costo en Bs = costo × tasa. El margen es sobre el precio de venta, no sobre el costo.
- Redondeo siempre hacia arriba a Bs 10 / 50 / 100.
- Calculadora inversa (precio actual → margen real) y tabla comparativa de márgenes 10 %–40 %.
- Desglose paso a paso con la fórmula aplicada, botón para copiar el precio y mensaje para el cliente.
- Caché offline: última tasa + fecha en SharedPreferences; sin conexión muestra el valor guardado.

## Ejemplo verificado

Costo $10,00 · tasa BCV 897,54 · margen 20 % · comisión 2 % · gasto fijo 0:

```
Costo en Bs = 10 × 897,54 = 8.975,40 Bs
Precio = 8.975,40 ÷ (1 − 0,02 − 0,20) = 8.975,40 ÷ 0,78 = 11.506,92 Bs
Comisión (2 %) = 230,14 Bs
Ganancia (20 %) = 2.301,38 Bs
Comprobación: 8.975,40 + 230,14 + 2.301,38 = 11.506,92 Bs ✓
```

## Tasas automáticas (valores reales del 2026-11-09)

| Tasa | Valor | Fuente |
|---|---|---|
| BCV dólar | 897,5383 Bs/$ | `GET https://ve.dolarapi.com/v1/dolares/oficial` (campo `promedio`) |
| Binance USDT P2P | 1045,00 Bs/USDT (mediana) | `POST https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search` `{fiat:"VES", asset:"USDT", tradeType:"BUY", page:1, rows:10}` → mediana de `adv.price` |
| Euro BCV | 1001,186 Bs/€ | `GET https://ve.dolarapi.com/v1/euros/oficial` |
| Personalizada | manual | la escribe el usuario, sin red |

Respaldo de Binance: `GET https://www.binance.com/bapi/c2c/v1/public/c2c/agent/quote-price?fiat=VES&asset=USDT&tradeType=BUY` (1043,50 verificado) y luego DolarApi paralelo `https://ve.dolarapi.com/v1/dolares/paralelo`. En app nativa **no hay bloqueo CORS** (ese bloqueo solo afecta a la web), así que Binance directo sí funciona aquí.

API key opcional de DolarVzla: se pega en Ajustes, se guarda solo en SharedPreferences del teléfono, nunca hardcodeada. Las 3 tasas principales funcionan sin key.

## Requisitos

- Flutter 3.38+ (SDK Dart ^3.8.0)
- Android Studio / SDK con API 36, Java 17

## Cómo compilar

```bash
flutter pub get
flutter analyze            # debe pasar sin errores
flutter test               # si agregas tests en test/
```

### AAB para Play Store (el formato obligatorio para apps nuevas)

```bash
flutter build appbundle --release
# Sale en: build/app/outputs/bundle/release/app-release.aab
```

### APK solo para pruebas en tu teléfono (NO sirve para publicar apps nuevas)

```bash
flutter build apk --release
# Sale en: build/app/outputs/flutter-apk/app-release.apk
```

## Keystore (firma de release) — lo hace Layan, una sola vez

1. Crear el keystore:
   ```bash
   keytool -genkeypair -v -keystore ~/margenesve-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias margenesve
   ```
2. Copiar `android/key.properties.example` a `android/key.properties` y completar `storePassword`, `keyPassword`, `keyAlias`, `storeFile` (ruta absoluta al `.jks`).
3. **Guarda copia del `.jks` y las contraseñas fuera del PC.** Si lo pierdes, no podrás actualizar la app en Play Store.
4. `android/key.properties` y `*.jks` **no** se suben a Git (ver `.gitignore` si agregas el repo).

## Estructura

```
lib/
  main.dart                  # Material 3, tema oscuro, navegación (3 pestañas)
  models/rate.dart           # Rate + RateSource (las 4 tasas)
  utils/format.dart          # fmtBs / fmtUsd / fmtRate (es-VE)
  services/
    rates_service.dart       # fetch con timeout 10 s, fallback en cadena, caché
    calculator.dart          # fórmula, redondeo, inversa, tabla 10–40 %
  screens/
    calculator_screen.dart   # inputs, 4 tarjetas de tasa, desglose, inversa, tabla
    rates_screen.dart        # tasas, fuentes, fecha, estado sin conexión
    settings_screen.dart     # API key DolarVzla opcional, acerca de
android/app/
  build.gradle.kts           # com.margenesve.calculadora, 1.0.0+1, targetSdk 36
  src/main/AndroidManifest.xml  # permiso INTERNET, label
  key.properties.example     # plantilla SIN secretos reales
```

## Privacidad

La app no recolecta cuentas ni datos personales. Solo consulta tasas públicas a DolarApi y Binance, y guarda en el teléfono la última tasa, la tasa personalizada y (opcional) la API key de DolarVzla. Ver `PRIVACY_POLICY.md`.
