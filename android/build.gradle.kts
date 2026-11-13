allprojects {
    repositories {
        google()
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/google")
        mavenCentral()
    }
}

subprojects {
    buildscript {
        repositories {
            google()
            maven("https://maven.aliyun.com/repository/central")
            maven("https://maven.aliyun.com/repository/public")
            maven("https://maven.aliyun.com/repository/google")
            mavenCentral()
        }
    }
    afterEvaluate {
        // Plugins compiled against older SDKs (file_picker pins android-34)
        // fail the AAR metadata check when a transitive dependency needs a
        // newer one — align every library module with the app's compileSdk.
        extensions.findByName("android")?.let { ext ->
            if (ext is com.android.build.gradle.LibraryExtension) {
                val current = ext.compileSdk
                if (current == null || current < 36) ext.compileSdk = 36
            }
        }
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
