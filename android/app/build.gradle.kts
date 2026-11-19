plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.graviton94.mintandfriends"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.graviton94.mintandfriends"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23) // Firebase 최소 23
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 카카오 로그인 키: CI 시크릿 KAKAO_NATIVE_APP_KEY → app.yml/aab.yml 이 HF_KAKAO_NATIVE_APP_KEY 로 넘긴다.
        manifestPlaceholders["kakaoScheme"] = "kakao" + (System.getenv("HF_KAKAO_NATIVE_APP_KEY")?.takeIf { it.isNotBlank() } ?: "none")

        // 시험용 APK 는 arm64 폰만 (app.yml --target-platform android-arm64). 스토어 AAB 는 모든 ABI.
        if (project.findProperty("target-platform")?.toString() == "android-arm64") {
            ndk { abiFilters += listOf("arm64-v8a") }
        }
    }

    signingConfigs {
        // 시험용 키: 폰에 직접 설치하는 APK. app.yml 이 keystore/sideload.jks.gpg 를
        // SIDELOAD_PASSPHRASE 시크릿으로 풀어 경로를 넘긴다. 없으면(로컬 빌드) 디버그 키.
        val sideloadStore = System.getenv("HF_SIDELOAD_STORE")?.takeIf { it.isNotBlank() && file(it).exists() }
        val sideloadPass = System.getenv("HF_SIDELOAD_PASSWORD").orEmpty()
        if (sideloadStore != null && sideloadPass.isNotBlank()) {
            create("sideload") {
                storeFile = file(sideloadStore)
                storePassword = sideloadPass
                keyAlias = "sideload"
                keyPassword = sideloadPass
            }
        }
        // Play 업로드 키: 네 변수가 모두 있을 때만 (aab.yml).
        val uploadStore = System.getenv("ANDROID_UPLOAD_KEYSTORE")?.takeIf { it.isNotBlank() && file(it).exists() }
        val uploadVars = listOf("ANDROID_UPLOAD_STORE_PASSWORD", "ANDROID_UPLOAD_KEY_ALIAS", "ANDROID_UPLOAD_KEY_PASSWORD")
            .map { System.getenv(it).orEmpty() }
        if (uploadStore != null && uploadVars.all { it.isNotBlank() }) {
            create("upload") {
                storeFile = file(uploadStore)
                storePassword = uploadVars[0]
                keyAlias = uploadVars[1]
                keyPassword = uploadVars[2]
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.findByName("sideload") ?: signingConfigs.getByName("debug")
        }
        release {
            // 코드 축소 규칙 (proguard-rules.pro): 실행 직후 꺼지던 WorkManager 문제 포함
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.findByName("sideload")
                ?: signingConfigs.getByName("debug")
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
