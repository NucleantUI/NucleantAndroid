import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// ── The Swift side ───────────────────────────────────────────────────────────
//
// The app's Swift is NucleantAndroid itself (the package two levels up): its
// DeviceLabBridge product, libDeviceLabBridge.so, cross-compiled here once per
// ABI with the installed Swift Android SDK. Then:
//
//   - the .so files it needs — itself, libSwiftJava.so, the Swift runtime
//     libraries it links (Android has no system Swift), libc++_shared.so — are
//     staged into build/generated/swiftJniLibs/<abi>/;
//   - the Java jextract generated for DeviceLabBridge, swift-java's
//     SwiftKitCore (which that Java calls into, and which is not published to
//     any Maven repository), and the package's own Java helpers (Android/java)
//     join the app's Java sources.

val swiftPackageDir: File = rootDir.parentFile
// Its own scratch directory: the host build (.build) may come from another
// compiler (Xcode's), and SwiftPM would reuse what that built for the host tools.
val swiftBuildDir = File(swiftPackageDir, ".build-android")
val swiftProduct = "DeviceLabBridge"
val swiftConfig = (findProperty("swift.config") as String?) ?: "debug"
val buildSwift = (findProperty("swift.build") as String?)?.toBoolean() ?: true

// The Swift Android SDK only carries triples from API 28 up; built for the
// lowest, the libraries load on every newer Android.
val swiftApiLevel = 28

data class SwiftAbi(val triple: String, val runtimeDir: String)

val knownAbis = mapOf(
    "arm64-v8a" to SwiftAbi("aarch64-unknown-linux-android", "swift-aarch64"),
    "x86_64" to SwiftAbi("x86_64-unknown-linux-android", "swift-x86_64"),
)
val swiftAbis: List<String> = ((findProperty("swift.abis") as String?) ?: "arm64-v8a,x86_64")
    .split(",").map { it.trim() }.filter { it.isNotEmpty() }
    .onEach { require(it in knownAbis) { "Unsupported ABI $it; supported: ${knownAbis.keys}" } }

/** The installed Swift Android SDK bundle, looked up where SwiftPM keeps them. */
fun swiftSdkBundle(): File {
    val home = File(System.getProperty("user.home"))
    val roots = listOf(
        File(home, "Library/org.swift.swiftpm/swift-sdks"),
        File(home, ".config/swiftpm/swift-sdks"),
        File(home, ".swiftpm/swift-sdks"),
    ).filter { it.isDirectory }
    val named = findProperty("swift.sdk") as String?
    val bundles = roots.flatMap { root ->
        root.listFiles { f -> f.isDirectory && f.name.endsWith("_android.artifactbundle") }?.toList() ?: emptyList()
    }
    val bundle = if (named != null) bundles.firstOrNull { it.name == "$named.artifactbundle" }
    else bundles.maxByOrNull { it.name }
    return bundle ?: throw GradleException(
        "No Swift Android SDK installed${named?.let { " named $it" } ?: ""}. Install it with " +
            "`swift sdk install <url> --checksum <sum>` (swift.org/install), then run the bundle's " +
            "swift-android/scripts/setup-android-sdk.sh with ANDROID_NDK_HOME set."
    )
}

/**
 * The swift executable: `swift.path`, else the toolchain whose version matches
 * the SDK (swift-6.3.3-RELEASE_android → swift-6.3.3-RELEASE.xctoolchain), else
 * `swift` on PATH. Xcode's swift cannot build with an open-source SDK.
 */
fun swiftExecutable(bundle: File): File {
    (findProperty("swift.path") as String?)?.let { return File(it) }
    val version = bundle.name.removeSuffix("_android.artifactbundle")
    val home = File(System.getProperty("user.home"))
    listOf(
        File(home, "Library/Developer/Toolchains/$version.xctoolchain/usr/bin/swift"),
        File("/Library/Developer/Toolchains/$version.xctoolchain/usr/bin/swift"),
    ).firstOrNull { it.isFile }?.let { return it }
    return File("swift")
}

// SwiftKitCore, from the swift-java checkout SwiftPM made — so it is always the
// revision whose jextract generated the bridge's Java. Two of its annotation
// types carry jdk.jfr's @Label/@Description, which android.jar does not have;
// they only document the annotations, so they are dropped on the way.
val swiftKitCoreDir = layout.buildDirectory.dir("generated/swiftKitCore")
val stageSwiftKitCore = tasks.register<Copy>("stageSwiftKitCore") {
    group = "swift"
    description = "Copy SwiftKitCore's Java out of the swift-java checkout, without its jdk.jfr annotations"
    from(File(swiftBuildDir, "checkouts/swift-java/SwiftKitCore/src/main/java"))
    into(swiftKitCoreDir)
    filter { line ->
        val code = line.trim()
        if (code.startsWith("import jdk.jfr.") || code.startsWith("@Label(") || code.startsWith("@Description(")) "" else line
    }
}

val ndkHostTag = if (System.getProperty("os.name").lowercase().contains("mac")) "darwin-x86_64" else "linux-x86_64"
val swiftJniLibsDir = layout.buildDirectory.dir("generated/swiftJniLibs")

val stageSwiftTasks = swiftAbis.map { abi ->
    val info = knownAbis.getValue(abi)
    val triple = "${info.triple}$swiftApiLevel"

    val compile = tasks.register<Exec>("buildSwift_$abi") {
        group = "swift"
        description = "swift build $swiftProduct for $abi"
        workingDir = swiftPackageDir
        executable = "swift"
        args(
            "build", "--product", swiftProduct, "-c", swiftConfig, "--swift-sdk", triple,
            "--scratch-path", swiftBuildDir.path, "--disable-sandbox",
        )
        doFirst {
            val swift = swiftExecutable(swiftSdkBundle())
            executable = swift.path
            // swift-java's build plugins run `swift` by name; it has to be this one.
            if (swift.parentFile != null) {
                environment("PATH", swift.parentFile.path + File.pathSeparator + System.getenv("PATH"))
            }
        }
    }

    tasks.register("stageSwift_$abi") {
        group = "swift"
        description = "Stage $swiftProduct and the Swift runtime it links into jniLibs/$abi"
        dependsOn(compile)
        val outDir = swiftJniLibsDir.map { it.dir(abi) }
        outputs.dir(outDir)
        doLast {
            val out = outDir.get().asFile
            out.deleteRecursively()
            out.mkdirs()

            val bundle = swiftSdkBundle()
            val ndk = android.ndkDirectory
            val readelf = File(ndk, "toolchains/llvm/prebuilt/$ndkHostTag/bin/llvm-readelf")
            // Where a needed library may come from; anything else is the system's.
            val searchDirs = listOf(
                File(swiftBuildDir, "$triple/$swiftConfig"),
                File(bundle, "swift-android/swift-resources/usr/lib/${info.runtimeDir}/android"),
                File(bundle, "swift-android/ndk-sysroot/usr/lib/${info.triple.replace("-unknown-linux-", "-linux-")}"),
            )

            // The product and, transitively, every library it needs from those.
            val pending = ArrayDeque(listOf("lib$swiftProduct.so"))
            val staged = mutableSetOf<String>()
            while (pending.isNotEmpty()) {
                val name = pending.removeFirst()
                if (!staged.add(name)) continue
                val lib = searchDirs.map { File(it, name) }.firstOrNull { it.isFile } ?: continue
                lib.copyTo(File(out, name), overwrite = true)

                val process = ProcessBuilder(readelf.path, "--needed-libs", lib.path).redirectErrorStream(true).start()
                val listing = process.inputStream.bufferedReader().readText()
                if (process.waitFor() != 0) throw GradleException("llvm-readelf failed on $lib: $listing")
                listing.lines().map { it.trim() }.filter { it.endsWith(".so") }.forEach(pending::addLast)
            }
            if ("lib$swiftProduct.so" !in out.list().orEmpty()) {
                throw GradleException("lib$swiftProduct.so was not built for $abi")
            }
            logger.lifecycle("Swift libraries for $abi: ${out.list()?.sorted()}")
        }
    }
}

android {
    namespace = "org.nucleantui.devicelab"
    compileSdk = 35
    ndkVersion = (findProperty("android.ndkVersion") as String?) ?: "27.3.13750724"

    defaultConfig {
        applicationId = "org.nucleantui.devicelab"
        // MediaStore saving (IS_PENDING, RELATIVE_PATH) and loadThumbnail are Android 10.
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
        ndk {
            abiFilters += swiftAbis
        }
    }

    sourceSets["main"].apply {
        java.srcDirs(
            File(swiftPackageDir, "Android/java"),
            File(swiftBuildDir, "plugins/outputs/nucleantandroid/$swiftProduct/destination/JExtractSwiftPlugin/src/generated/java"),
            swiftKitCoreDir.get().asFile,
        )
        jniLibs.srcDir(swiftJniLibsDir)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

if (buildSwift) {
    // SwiftKitCore comes out of the checkout the Swift build makes.
    stageSwiftKitCore.configure { dependsOn(stageSwiftTasks) }
}
tasks.named("preBuild") {
    dependsOn(stageSwiftKitCore)
    if (buildSwift) {
        dependsOn(stageSwiftTasks)
    }
}
