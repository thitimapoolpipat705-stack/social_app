plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")          // ✅ ใช้ id ใหม่ของ Kotlin Android
    id("com.google.gms.google-services")        // ✅ Firebase
    id("dev.flutter.flutter-gradle-plugin")     // ✅ Flutter plugin ต้องตามหลัง Android/Kotlin
}

android {
    namespace = "com.example.social_app"

    // ใช้ค่ามาตรฐานของ Flutter หรือกำหนดเป็นตัวเลขก็ได้ (เช่น 34)
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.social_app"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // เผื่อโปรเจกต์มี method เกิน 64k (ปลอดภัยไว้ก่อน)
        multiDexEnabled = true

        // ✅ สำคัญ: ให้แอประบุ applicationName แบบปกติ (ไม่ใช้ SplitCompat)
        // ตรงกับ AndroidManifest: android:name="${applicationName}"
        manifestPlaceholders += mapOf(
            "applicationName" to "io.flutter.app.FlutterApplication"
        )
    }

    buildTypes {
        release {
            // ยังใช้ debug keystore ชั่วคราว (ค่อยเปลี่ยนเป็น release.keystore ภายหลัง)
            signingConfig = signingConfigs.getByName("debug")

            // ✅ ปิด shrink ตอนนี้ เพื่อกัน R8 ตัดคลาสจน build ล้ม
            isMinifyEnabled = false
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // กันจอดำจาก shrink/obfuscate ตอนดีบัก (ปกติ false อยู่แล้ว)
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // กัน collision บาง lib (ไม่ใส่ก็ได้ แต่ช่วยลด warning)
    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*"
            )
        }
    }
}

flutter {
    source = "../.."
}

// ถ้า minSdk < 21 ค่อยเปิดตัวนี้ (ของคุณ minSdk=23 ไม่ต้อง)
// dependencies {
//     implementation("androidx.multidex:multidex:2.0.1")
// }
