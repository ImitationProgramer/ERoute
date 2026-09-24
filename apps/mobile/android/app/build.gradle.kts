import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    buildFeatures { buildConfig = true }
    sourceSets.getByName("main").java.srcDir("src/main/kotlin")
    flavorDimensions += "environment"
    productFlavors {
        create("dev") { dimension = "environment" }
        create("production") { dimension = "environment" }
        create("preview") {
            dimension = "environment"
            applicationIdSuffix = ".preview"
            versionNameSuffix = "-ui-preview"
        }
    }
    namespace = "com.eroute.eroute_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        val defines = (project.findProperty("dart-defines") as? String ?: "")
            .split(",").filter { it.isNotBlank() }.mapNotNull {
                runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull()
            }.associate { val p = it.split("=", limit = 2); p[0] to p.getOrElse(1) { "" } }
        buildConfigField("boolean", "EMERGENCY_ENABLED", (defines["ENABLE_SYSTEM_EMERGENCY_DIALER"] == "true").toString())
        buildConfigField("boolean", "AUTOMATION", (defines["EROUTE_AUTOMATION"] != "false").toString())
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.eroute.eroute_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// UI fixtures must never be packaged through a normal or distributable target.
val memberPreviewTarget = providers.gradleProperty("target").orNull?.endsWith("main_ui_preview.dart") == true
gradle.taskGraph.whenReady {
    val taskNames = allTasks.map { it.name.lowercase() }
    val previewBuild = taskNames.any { it.contains("preview") && (it.startsWith("assemble") || it.startsWith("bundle") || it.startsWith("compileflutter")) }
    val nonDebugPreview = taskNames.any { it.contains("previewrelease") || it.contains("previewprofile") }
    if (nonDebugPreview || memberPreviewTarget && !previewBuild) {
        throw GradleException("UI preview is restricted to the preview debug variant.")
    }
}
