# SevenRoses

Proyecto Flutter con dos experiencias: la tienda web para clientas y la app
Android/iOS para administradoras. Firebase Authentication y Cloud Firestore
permiten compartir el catálogo, las existencias y los pedidos en tiempo real.

## Modo local

Sin configuración Firebase, la tienda y la app se pueden ejecutar como demo
local. Los datos no se comparten entre instancias.

```powershell
flutter pub get
flutter run -d chrome
```

En otra terminal, conecta un teléfono Android con depuración USB y ejecuta:

```powershell
flutter devices
flutter run -d ID_DEL_DISPOSITIVO
```

Acceso local de demostración:

- Teléfono: `+50255550123`
- Contraseña: `SevenRoses2026!`

Esta cuenta es solo para probar la interfaz; no es una cuenta de Firebase ni
protege una tienda real.

## Activar sincronización gratuita con Firebase

El nivel gratuito Spark puede servir para probar Authentication y Firestore
dentro de sus límites vigentes. La configuración debe hacerse en una cuenta
Firebase propia; no compartas aquí claves, archivos de credenciales ni tokens.

1. Crea un proyecto en [Firebase Console](https://console.firebase.google.com/).
2. Crea una base Firestore en modo producción y activa los proveedores
   **Anonymous** y **Google** en Authentication.
3. Registra una app web y una app Android. En Android usa el identificador de
   paquete que aparece en [android/app/build.gradle.kts](./android/app/build.gradle.kts) y registra las huellas SHA
   de la clave de firma de depuración. Para Google Sign-In, configura el cliente
   OAuth web como `GOOGLE_SERVER_CLIENT_ID`.
4. Copia los valores públicos de configuración del proyecto y las reglas de
   [firestore.rules](./firestore.rules) en la sección **Firestore Database >
   Rules** de Firebase Console y publícalas.
5. Inicia primero la app Android con Firebase configurado y entra con Google.
   En Firebase Authentication, copia el UID de esa cuenta; en Firestore crea un
   documento vacío con ese UID en la colección `admins`. Cierra sesión y vuelve
   a entrar. Solo los UID incluidos en `admins` podrán administrar los datos.
6. La app administradora publicará los productos demo si el catálogo remoto
   está vacío. Luego inicia Chrome con la misma configuración; las compras
   anónimas descuentan existencias en Firestore y aparecen en los pedidos y
   ventas de la app administradora.

Ejemplo PowerShell (reemplaza los valores con los de tu proyecto):

```powershell
flutter run -d chrome `
  --dart-define=FIREBASE_API_KEY=TU_API_KEY `
  --dart-define=FIREBASE_WEB_APP_ID=TU_APP_ID_WEB `
  --dart-define=FIREBASE_ANDROID_APP_ID=TU_APP_ID_ANDROID `
  --dart-define=FIREBASE_PROJECT_ID=TU_PROJECT_ID `
  --dart-define=FIREBASE_SENDER_ID=TU_SENDER_ID
```

La app elige el ID de Firebase según la plataforma. Para teléfono Android,
reemplaza `chrome` por el ID que muestre `flutter devices`; se usa
`FIREBASE_ANDROID_APP_ID`. Para iOS, registra también la app iOS y configura
`FIREBASE_IOS_APP_ID`. Si solo defines `FIREBASE_APP_ID`, se usa ese valor como
alternativa en todas las plataformas.

Al ejecutar en Android, añade:

```powershell
--dart-define=GOOGLE_SERVER_CLIENT_ID=TU_CLIENT_ID_OAUTH_WEB
```

`FIREBASE_AUTH_DOMAIN` es opcional. Los valores `FIREBASE_*` son configuración
pública del cliente, no sustituyen reglas de Firestore. No agregues credenciales
privadas de AWS o Google al código ni al APK. La sesión de compra web es
anónima; las administradoras se autorizan mediante `admins/{uid}`.

## Límites importantes

- Los pedidos y pagos son simulados; no se cobra una tarjeta ni se confirma una
  transferencia real. No uses las reglas de demostración como garantía de
  pagos, precios o ventas contra fraude.
- Las notificaciones se muestran en la app mientras está abierta. Recibir push
  con la app cerrada necesita configurar FCM y un emisor backend por separado.
- Las fotos pequeñas capturadas (hasta 500 KB) se guardan en Firestore para
  sincronizarlas; las más grandes no se suben. No se usa Firebase Storage.
- El mapa OpenStreetMap y las ubicaciones/rutas son ilustrativos, no rastreo GPS
  real.
- Los reportes/Excel no son exportaciones automáticas persistentes en esta
  integración.
- Rekognition continúa siendo opcional y requiere credenciales AWS temporales
  configuradas localmente; nunca incluyas claves AWS en una compilación
  distribuible.

## Funciones de la demo

- Catálogo web, búsqueda, bolsa de compra y pedidos con códigos `#SR-...`.
- App administrativa con inventario, ventas automáticas en quetzales y Google
  Sign-In opcional cuando Firebase está configurado.
- Escáner de código de barras con cámara y asistente de preguntas frecuentes
  basado en el catálogo.
- Sincronización Firestore en tiempo real cuando ambas plataformas usan el
  mismo proyecto Firebase.
