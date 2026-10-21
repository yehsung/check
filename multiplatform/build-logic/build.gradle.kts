plugins {
    `kotlin-dsl`
}

dependencies {
    implementation(libs.gradleplugin.kotlin)
    implementation(libs.gradleplugin.kotlin.serialization)
    implementation(libs.gradleplugin.compose.compiler)
    implementation(libs.gradleplugin.compose)
    implementation(libs.gradleplugin.agp)
    implementation(libs.gradleplugin.roborazzi)
}
