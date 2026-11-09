# Checklist Play Store — Calculadora de Márgenes VE

> Nada de esto está hecho todavía: este archivo es la lista para que Layan lo haga paso a paso. No se publicó nada, no se creó cuenta ni keystore.

## 1. Cuenta de Play Console (solo Layan)

- [ ] Crear cuenta en [Google Play Console](https://play.google.com/console) — **$25 pago único** con tarjeta (Mercantil Panamá sirve; BDV no, porque Google cobra en USD).
- [ ] Tipo de cuenta: **personal** (es lo que corresponde a una app individual).
- [ ] Verificación de identidad: Google pide documento de identidad y puede tardar 1–3 días.

## 2. Antes de subir: la app

- [ ] Keystore de release creado (ver `README.md` → `android/key.properties`). Guardar copia del `.jks` + contraseñas fuera del PC.
- [ ] `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`
  - Formato obligatorio para apps nuevas: **AAB, no APK**. El APK solo sirve para probar en tu teléfono.
- [ ] Datos del paquete: `applicationId com.margenesve.calculadora`, versión `1.0.0+1`, `targetSdk 36` (Android 16), `minSdk 21`.
- [ ] Icono de la app 512×512 PNG (fondo sólido, sin transparencia) — **pendiente: diseño final**.
- [ ] Capturas de pantalla: mínimo 2 (recomendado 4–8), teléfono 1080×1920 o similar. Tomarlas de la app real con datos de ejemplo: calculadora con desglose, tarjetas de tasas, tabla 10–40 %.
- [ ] Gráfico de funciones (feature graphic) 1024×500 — opcional pero recomendado.
- [ ] Probar el AAB en un teléfono real antes de subirlo (instalar el APK de release o usar prueba interna).

## 3. Ficha de la tienda (en español)

- Nombre: **Calculadora de Márgenes VE**
- Descripción corta (máx. 80 caracteres), sugerencia: `Precio en bolívares sin perder: costo, tasa BCV/Binance y margen.`
- Descripción larga: qué hace, la fórmula, las 4 tasas (BCV dólar, Binance USDT, Euro BCV, personalizada), redondeo hacia arriba, calculadora inversa, tabla 10–40 %, modo sin conexión.
- Categoría: Finanzas (o Herramientas).
- Correo de contacto: el de soporte de Refill Store o uno personal que revises (obligatorio en la ficha).
- Política de privacidad: URL pública con el contenido de `PRIVACY_POLICY.md` (puede alojarse en recargasrefillstore.com/privacidad-calculadora o en un Docs público; Play exige una URL, no un archivo).

## 4. Data Safety (formulario de seguridad de datos)

- La app **no recolecta datos personales ni cuentas**. Declarar:
  - No se recopilan datos de usuario.
  - No se comparten datos con terceros.
  - Conexiones de red: solo consultas a APIs públicas de tasas (DolarApi, Binance). La API key opcional de DolarVzla vive solo en el teléfono.
- Si en el futuro se agrega analítica o cuentas, hay que actualizar este formulario antes de publicar la actualización.

## 5. Clasificación de contenido

- [ ] Completar el cuestionario de clasificación (la app es una calculadora financiera, sin contenido sensible): debería salir **Para todo público / PEGI 3**.
- [ ] Declarar que la app no tiene anuncios (si no se agregan) y que no tiene compras dentro de la app.

## 6. Prueba cerrada — OBLIGATORIA para cuentas personales nuevas (2026)

- [ ] Crear una versión en **Prueba cerrada** (Closed testing) con el AAB.
- [ ] Reclutar **12 testers** (mínimo) con correos Gmail: familiares, amigos, clientes de Refill Store que quieran probar.
- [ ] Los 12 deben instalar la app y **permanecer 14 días** en la prueba antes de poder pedir producción. Google cuenta los días desde que el tester instala y abre la app.
- [ ] Recoger fallos/comentarios de esos 14 días y corregirlos antes de producción.
- [ ] Solo después de los 14 días: solicitar acceso a producción en Play Console y esperar la revisión de Google (normalmente 1–7 días).

## 7. Producción

- [ ] Subir el mismo AAB (o uno nuevo con versionCode mayor) a Producción.
- [ ] Revisión de Google → publicación. Avisar en Refill Store / redes cuando esté viva.
- [ ] Plan de actualizaciones: cada cambio de versión sube `versionCode` (+1) y `versionName` en `pubspec.yaml` y `build.gradle.kts`.

## Resumen de lo que solo Layan puede hacer

| Pendiente | Por qué solo él |
|---|---|
| Cuenta Play Console ($25) | Pago + identidad personal |
| Keystore + `key.properties` | Firma legal de la app; si lo pierde, no hay actualización |
| Icono final 512×512 | Decisión de diseño/marca |
| Capturas + ficha en español | Textos e imágenes de su producto |
| 12 testers por 14 días | Sus contactos |
| Subir el AAB | Su cuenta de Play Console |
