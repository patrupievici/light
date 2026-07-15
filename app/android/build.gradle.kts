import com.android.build.api.dsl.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            // home_widget uses `glance-appwidget:1.+` which can resolve to 1.3 alpha and
            // requires compileSdk 37 + AGP 9.1 — keep the stack on AGP 8.11 / SDK 36.
            if (requested.group == "androidx.glance" && requested.name == "glance-appwidget") {
                useVersion("1.1.1")
                because("Glance 1.3+ alpha requires compileSdk 37 and AGP 9.1")
            }
            if (requested.group == "androidx.work" && requested.name.startsWith("work-runtime")) {
                useVersion("2.11.2")
                because("home_widget declares 2.+; pin the current stable release instead of resolving an alpha")
            }
        }
    }
}

subprojects {
    if (name == "home_widget") {
        afterEvaluate {
            extensions.configure<LibraryExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
            tasks.withType<KotlinJvmCompile>().configureEach {
                compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
