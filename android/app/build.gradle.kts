import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// keystore de release: se lee de android/key.properties (NO versionado).
// Copia android/key.properties.example a android/key.properties y
// completa tus datos. Sin ese archivo, el build de release falla con
// un mensaje claro; el build debug no lo necesita.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.margenesve.calculadora"
    compileSdk = 36
    // Añadido del template de Flutter 3.47: sin esto, AGP 9.1 + Kotlin 2.4
    // no fijan JVM 17 ni NDK (nuestro archivo original no los traía).
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.margenesve.calculadora"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Con key.properties: firma de release (Play Store).
            // Sin key.properties: firma debug, solo para probar el AAB/APK
            // en tu teléfono; ese artefacto NO se sube a Play Store.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

flutter {
    source = "../.."
}
