# Política de Privacidad — Calculadora de Márgenes VE

**Última actualización: 9 de noviembre de 2026**

## 1. Qué hace la app

Calculadora de Márgenes VE es una calculadora para vendedores en Venezuela: a partir del costo de un producto en dólares, la tasa de cambio del día, las comisiones y el margen deseado, calcula el precio de venta en bolívares.

## 2. Privacidad y Cuenta Opcional en la Nube

La aplicación puede utilizarse **sin crear cuenta** en modo 100 % local:

- No pedimos ubicación, contactos, micrófono ni cámara.
- No usamos publicidad de terceros.
- **Sincronización opcional (Firebase Auth y Cloud Firestore):** si decides iniciar sesión (con correo y contraseña o como invitado), tu catálogo de productos y tu historial de cálculos se respaldan de forma privada bajo tu identificador de usuario (`users/{uid}`) en Google Cloud Firestore, protegidos por reglas de seguridad para que solo tú puedas leerlos o modificarlos.

## 3. Datos guardados solo en tu teléfono

Lo siguiente se guarda únicamente en el almacenamiento local del teléfono (SharedPreferences) y nunca sale de él:

- La última tasa consultada, el historial reciente de fluctuaciones y su fecha (para mostrarlos sin conexión).
- La tasa personalizada que escribas, así como la copia local de tu catálogo de productos, historial de cálculos y plantillas/presets guardados.
- **Perfil de vendedor (Pago Móvil):** si decides configurar tu nombre comercial, RIF o cédula, número de teléfono, banco y notas de cobro, estos datos se almacenan **exclusivamente en el dispositivo** con el único fin de autocompletar el texto del mensaje de cobro que tú mismo copias o compartes. **Nunca se transmiten a ningún servidor propio ni de terceros.**

Puedes borrar estos datos desinstalando la app o borrando sus datos desde Ajustes de Android.

## 4. Conexiones de red

La app consulta tasas de cambio públicas de estas fuentes:

- **DolarApi** (ve.dolarapi.com): tasa oficial BCV dólar y Euro BCV.
- **Binance** (p2p.binance.com y binance.com): cotización P2P de USDT en bolívares.

Esas consultas son peticiones estándar a APIs públicas; la app no envía en ellas ningún dato personal tuyo.

## 5. Permisos

La app solicita únicamente el permiso de **Internet**, necesario para consultar las tasas. No solicita cámara, micrófono, contactos, archivos ni ubicación.

## 6. Menores de edad

La app es una calculadora financiera de uso general y no está dirigida a menores de 13 años, aunque no recolecta datos de ningún usuario.

## 7. Cambios a esta política

Si en el futuro la app agrega funciones que impliquen datos (por ejemplo, cuentas o analítica), esta política se actualizará antes de publicar esa versión.

## 8. Contacto

Para preguntas sobre esta política: soporte@recargasrefillstore.com
