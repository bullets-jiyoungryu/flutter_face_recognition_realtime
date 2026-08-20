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
// 서드파티 플러그인의 JVM 타깃 정렬.
//
// tflite_flutter 0.12.1처럼 android { compileOptions }를 Java 11로 선언해 두고 KGP(Kotlin
// Gradle Plugin)는 직접 적용하지 않는 플러그인이 있다. 이 경우 Flutter Gradle 플러그인이
// 대신 `kotlin-android`를 적용하는데(FlutterPluginUtils.detectApplyingKotlinGradlePlugin),
// 이때 jvmTarget이 지정되지 않아 KGP 기본값인 17로 컴파일된다. 그 결과
// compileDebugJavaWithJavac(11)과 compileDebugKotlin(17)이 어긋나
// "Inconsistent JVM-target compatibility" 오류가 난다.
//
// 플러그인 쪽에 이를 고친 릴리스가 아직 없으므로(tflite_flutter는 0.12.1이 최신),
// 앱과 동일하게 모든 서브프로젝트의 Java/Kotlin 타깃을 17로 통일한다.
// 아래 evaluationDependsOn(":app")이 :app을 즉시 평가시키므로, afterEvaluate를 등록하려면
// 이 블록이 반드시 그보다 **앞에** 있어야 한다.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
