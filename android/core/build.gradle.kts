plugins {
    id("com.android.library")
}

android {
    namespace = "com.appshub.bettbox.core"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        minSdk = 26
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        release {
            isJniDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // libmeta.so 是 Go 用 -w -s 编译的，本身已无调试符号。
            // 跳过 AGP 的 strip，避免 llvm-strip 把 71MB 的库整体映射进内存导致 OOM。
            keepDebugSymbols += "**/libmeta.so"
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.annotation:annotation-jvm:1.9.1")
}

val copyNativeLibs by tasks.register<Copy>("copyNativeLibs") {
    doFirst {
        delete("src/main/jniLibs")
    }
    from("../../libclash/android")
    into("src/main/jniLibs")
}

afterEvaluate {
    tasks.named("preBuild") {
        dependsOn(copyNativeLibs)
    }
}