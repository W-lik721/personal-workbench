import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式签名配置（key.properties 不入库，见 .gitignore）
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.qingdeng.lite_workbench"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 依赖 java.time，需开启 core library desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.qingdeng.lite_workbench"
        // minSdk 由 local.properties 的 flutter.minSdkVersion 控制（当前 = 21）。
        // google_mlkit_text_recognition（拍照识题 OCR 引擎）要求 >= 21。
        // 用 local.properties 而不是硬编码，避免 Flutter 自动升级 build.gradle.kts 时覆盖。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 只打 arm64-v8a：覆盖 99% 现代安卓手机，APK 体积减半
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8 压缩/混淆/资源收缩全部关闭：新引入的 google_mlkit_text_recognition、
            // image_picker 等原生插件在 R8 tree-shaking 下会被剥离运行时所需类，
            // 导致 GeneratedPluginRegistrant 启动时找不到类而闪退。个人 App 稳定性优先，
            // 关闭后包体略增（已含 OCR 模型约 +几 MB），但不再有混淆相关崩溃。
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    // desugar_jdk_libs：让低版本 Android 也能用 java.time（flutter_local_notifications 需要）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // 拍照识题 OCR：Google ML Kit 中文识别模型（插件默认只含拉丁字母，中文需单独引入）
    implementation("com.google.mlkit:text-recognition-chinese:16.0.0-beta6")
}
