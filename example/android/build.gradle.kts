allprojects {
    repositories {
        google()
        mavenCentral()
        // The Reception Android SDK published by `./gradlew :reception:publishToMavenLocal` until it is on Maven
        // Central (see CLAUDE.md). Only the example looks here; the plugin's own build file never does.
        mavenLocal()
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
