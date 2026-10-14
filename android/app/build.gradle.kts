plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.chomusuke.tachyon"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    androidResources {
        localeFilters += listOf("es", "en")
        ignoreAssetsPattern = "!.svn:!.git:!.ds_store:!*.scc:.*:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~:!*.wasm:!*.js"
    }

    defaultConfig {
        applicationId = "dev.chomusuke.tachyon"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    splits {
        abi {
            isEnable = project.hasProperty("split-per-abi")
            reset()
            include("arm64-v8a", "x86_64", "armeabi-v7a")
            // Generate both per-ABI APKs and the universal (fat) APK.
            isUniversalApk = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Excluir archivos Web (.wasm, .js) e íconos de escritorio (.ico) de flutter_assets
tasks.withType<Copy>().configureEach {
    if (name.startsWith("copyFlutterAssets")) {
        exclude(
            "**/packages/haudiotagger/pkg/**",
            "**/*.wasm",
            "**/*.js",
            "**/*.ico"
        )
    }
}