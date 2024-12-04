import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}

android {
    compileSdk = 34

    defaultConfig {
        applicationId = "com.tinkooladik.actions_test"
        minSdk = 21
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            storeFile = file("keystore.keystore")
            storePassword = "asdasd"
            keyAlias = "a"
            keyPassword = "asdasd"
        }
    }
    //test 0.5.0

    buildTypes {
        create("prod") {
            initWith(getByName("release"))
            matchingFallbacks.add("release")
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
        }

        create("qa") {
            initWith(getByName("debug"))
            matchingFallbacks.add("debug")
            applicationIdSuffix = ".debug"
            resValue("string", "app_name", "ServusTV On QA")
        }

        create("dev") {
            initWith(getByName("debug"))
            matchingFallbacks.add("debug")
            applicationIdSuffix = ".dev"
            isDefault = true
            resValue("string", "app_name", "ServusTV On Dev")
            buildConfigField(
                type = "Boolean",
                name = "enableDevSettings",
                value = "true"
            )
        }

        all {
            buildConfigField(
                type = "Boolean",
                name = "enableDevSettings",
                value = "false"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
    }

    packagingOptions {
        resources {
            excludes += setOf(
                "META-INF/ASL-2.0.txt",
                "META-INF/ASL-3.0.txt",
                "META-INF/LGPL-3.0.txt"
            )
        }
    }

    namespace = "com.tinkooladik.actions_test"
}

dependencies {
    implementation("androidx.core:core-ktx:1.7.0")
    implementation("androidx.appcompat:appcompat:1.3.0")
    implementation("com.google.android.material:material:1.5.0-alpha04")
    implementation("androidx.constraintlayout:constraintlayout:2.0.4")
    implementation("androidx.navigation:navigation-fragment-ktx:2.3.5")
    implementation("androidx.navigation:navigation-ui-ktx:2.3.5")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.3")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.4.0")

    // Uncomment this line if needed
    // implementation("com.redbull:rbak-analytics-android:1.0.3")
}

val localPropertyFile = rootProject.file("local.properties")
val localProperties = Properties().apply {
    if (localPropertyFile.canRead()) {
        load(FileInputStream(localPropertyFile))
    }
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components.findByName("release"))
                groupId = "com.tinkooladik"
                artifactId = "github_actions"
                version = "0.4.2"
            }
        }

        repositories {
            maven {
                name = "GitHubPackagesTest"
                url = uri("https://maven.pkg.github.com/tinkooladik/github_actions")

                credentials {
                    username = localProperties["gpr.user"]?.toString()
                        ?: System.getenv("GITHUB_ACTOR")
                    password = localProperties["gpr.key"]?.toString()
                        ?: System.getenv("GITHUB_TOKEN")
                }
            }
        }
    }
}
