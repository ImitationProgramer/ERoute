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
    project.evaluationDependsOn(":app")
    // AGP 9 legacy-Kotlin mode needs the Kotlin directory explicitly included.
    // Naver already declares this; package_info_plus assumes built-in Kotlin.
    if (name == "package_info_plus") {
        afterEvaluate {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                sourceSets.getByName("main").java.srcDir("src/main/kotlin")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
