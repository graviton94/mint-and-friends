import groovy.json.JsonSlurper

// ---------------------------------------------------------------- 앱 설정 (config/app_config.json)
// Dart 쪽과 같은 파일을 읽어 카카오 네이티브 앱 키를 매니페스트에 넣는다.
val appConfig: Map<*, *> = rootProject.file("../config/app_config.json").let { f ->
    if (f.exists()) JsonSlurper().parse(f) as Map<*, *> else emptyMap<String, Any>()
}
val kakaoNativeAppKey: String = (appConfig["KAKAO_NATIVE_APP_KEY"] as? String) ?: ""

// ---------------------------------------------------------------- 서명
// 두 가지 키:
//  - upload   : Play 스토어 업로드용 (AAB). Play App Signing 에 등록된 업로드 키.
//  - sideload : 직접 배포용 APK (테스터 설치 등).
// CI 는 GPG 로 암호화된 키스토어(android/keystores/*.jks.gpg)를 패스프레이즈 시크릿으로 풀고
// 아래 환경변수를 채운다. 키스토어/키 비밀번호 = 패스프레이즈. (docs/RELEASE.md)
//   SIGNING_PROFILE = upload | sideload   (없으면 디버그 키)
//   ANDROID_UPLOAD_KEYSTORE, ANDROID_UPLOAD_PASSPHRASE, ANDROID_UPLOAD_ALIAS(기본 upload)
//   SIDELOAD_KEYSTORE, SIDELOAD_PASSPHRASE, SIDELOAD_ALIAS(기본 sideload)
fun env(name: String): String? = System.getenv(name)?.takeIf { it.isNotBlank() }
val signingProfile: String? = env("SIGNING_PROFILE")

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.graviton94.bloom_merge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.graviton94.bloomgarden"
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
        manifestPlaceholders["kakaoNativeAppKey"] = kakaoNativeAppKey
    }

    signingConfigs {
        create("upload") {
            env("ANDROID_UPLOAD_KEYSTORE")?.let { path ->
                storeFile = file(path)
                storePassword = env("ANDROID_UPLOAD_PASSPHRASE")
                keyPassword = env("ANDROID_UPLOAD_PASSPHRASE")
                keyAlias = env("ANDROID_UPLOAD_ALIAS") ?: "upload"
            }
        }
        create("sideload") {
            env("SIDELOAD_KEYSTORE")?.let { path ->
                storeFile = file(path)
                storePassword = env("SIDELOAD_PASSPHRASE")
                keyPassword = env("SIDELOAD_PASSPHRASE")
                keyAlias = env("SIDELOAD_ALIAS") ?: "sideload"
            }
        }
    }

    buildTypes {
        release {
            val chosen = signingProfile?.let { signingConfigs.findByName(it) }
            signingConfig = if (chosen?.storeFile != null) chosen else signingConfigs.getByName("debug")
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
