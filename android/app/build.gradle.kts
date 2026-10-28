import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

val mStoreFile = file("keystore.jks")
val mStorePassword: String? = localProperties.getProperty("storePassword")
val mKeyAlias: String? = localProperties.getProperty("keyAlias")
val mKeyPassword: String? = localProperties.getProperty("keyPassword")
val isRelease = mStoreFile.exists() && mStorePassword != null && mKeyAlias != null && mKeyPassword != null

android {
    namespace = "com.appshub.bettbox"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lsh.bettbox"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    signingConfigs {
        if (isRelease) {
            create("release") {
                storeFile = mStoreFile
                storePassword = mStorePassword
                keyAlias = mKeyAlias
                keyPassword = mKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isDebuggable = false
            signingConfig = signingConfigs.getByName(if (isRelease) "release" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/libmeta.so"
            // 只出 arm64-v8a。部分插件 AAR 自带 v7a/x86_64 的 .so，
            // 而内核 libmeta.so 只有 arm64，其它 ABI 装上也跑不起来，直接排除。
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        }
    }

    applicationVariants.all {
        outputs.all {
            (this as? com.android.build.gradle.internal.api.ApkVariantOutputImpl)?.versionCodeOverride = flutter.versionCode
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":core"))
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("com.android.tools.smali:smali-dexlib2:3.0.9") {
        exclude(group = "com.google.guava", module = "guava")
    }
    implementation("androidx.core:core-splashscreen:1.0.1")
}

configurations.all {
    resolutionStrategy {
        eachDependency {
            if (requested.group == "androidx.datastore") useVersion("1.1.2")
        }
    }
}
