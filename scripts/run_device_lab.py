# /// script
# requires-python = ">=3.13"
# ///
"""Build Device Lab (Demo/) and run it on an emulator — or a connected device.

    uv run scripts/run_device_lab.py            # create/boot the AVD, build, install, launch
    uv run scripts/run_device_lab.py --logcat   # ... and follow the app's log

Steps, each skipped when already done:

1. An AVD named `DeviceLab` from the newest installed system image for this
   Mac's architecture, with both cameras emulated: the back one is the virtual
   3D scene, the front one a moving test pattern. (Emulators have no flash.)
2. The emulator booted, unless a device is already connected.
3. `./gradlew :app:installDebug` for the device's ABI only — Gradle
   cross-compiles NucleantAndroid's DeviceLabBridge with the Swift Android SDK.
4. The app launched.

Needs the Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT, ~/.kivyschool/android-sdk
or ~/Library/Android/sdk), a JDK 17+ (JAVA_HOME), and the Swift Android SDK
installed for the toolchain in use; it installs none of them.
"""

from __future__ import annotations

import argparse
import os
import platform
import subprocess
import sys
import time
from pathlib import Path
from typing import NoReturn

PACKAGE_DIR = Path(__file__).resolve().parent.parent
DEMO_DIR = PACKAGE_DIR / "Demo"
APP_ID = "org.nucleantui.devicelab"
AVD_NAME = "DeviceLab"


def log(message: str) -> None:
    print(f"[device-lab] {message}", flush=True)


def die(message: str) -> NoReturn:
    sys.exit(f"[device-lab] error: {message}")


def android_sdk() -> Path:
    candidates = [
        os.environ.get("ANDROID_HOME"),
        os.environ.get("ANDROID_SDK_ROOT"),
        str(Path.home() / ".kivyschool/android-sdk"),
        str(Path.home() / "Library/Android/sdk"),
    ]
    for candidate in candidates:
        if candidate and (Path(candidate) / "platform-tools/adb").is_file():
            return Path(candidate)
    die("no Android SDK found; set ANDROID_HOME")


def swift_android_sdk_installed() -> bool:
    roots = [
        Path.home() / "Library/org.swift.swiftpm/swift-sdks",
        Path.home() / ".config/swiftpm/swift-sdks",
        Path.home() / ".swiftpm/swift-sdks",
    ]
    return any(any(root.glob("*_android.artifactbundle")) for root in roots if root.is_dir())


def run(args: list[str | Path], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(a) for a in args], text=True, **kwargs)


def output(args: list[str | Path]) -> str:
    return run(args, capture_output=True, check=False).stdout.strip()


# ---------------------------------------------------------------------------
# AVD
# ---------------------------------------------------------------------------


def system_image(sdk: Path) -> tuple[str, Path]:
    """The newest installed image for this Mac's ABI, preferring Google APIs."""
    abi = "arm64-v8a" if platform.machine() == "arm64" else "x86_64"
    rank = {"google_apis_playstore": 3, "google_apis": 2, "default": 1}
    images = []
    for path in (sdk / "system-images").glob(f"android-*/*/{abi}"):
        api = path.parent.parent.name.removeprefix("android-")
        if api.isdigit():
            images.append((int(api), rank.get(path.parent.name, 0), path))
    if not images:
        die(f"no {abi} system image under {sdk / 'system-images'}")
    api, _, path = max(images)
    package = f"system-images;android-{api};{path.parent.name};{abi}"
    return package, path


def ensure_avd(sdk: Path) -> None:
    emulator = sdk / "emulator/emulator"
    if AVD_NAME in output([emulator, "-list-avds"]).split():
        return
    package, _ = system_image(sdk)
    avdmanager = sdk / "cmdline-tools/latest/bin/avdmanager"
    log(f"creating AVD {AVD_NAME} from {package}")
    run(
        [avdmanager, "create", "avd", "-n", AVD_NAME, "-k", package, "-d", "pixel_7", "--force"],
        input="no\n",
        check=True,
    )
    config = Path.home() / f".android/avd/{AVD_NAME}.avd/config.ini"
    settings = {
        "hw.camera.back": "virtualscene",
        "hw.camera.front": "emulated",
        "hw.keyboard": "yes",
        "hw.gpu.enabled": "yes",
        # Software rendering: with the host GPU (auto/host) the emulator window
        # stays black on Macs with two GPUs, while the guest renders fine.
        "hw.gpu.mode": "swiftshader_indirect",
    }
    lines = [
        line for line in config.read_text().splitlines()
        if line.split("=", 1)[0].strip() not in settings
    ]
    lines += [f"{key}={value}" for key, value in settings.items()]
    config.write_text("\n".join(lines) + "\n")


def connected_devices(adb: Path) -> list[str]:
    lines = output([adb, "devices"]).splitlines()[1:]
    return [line.split()[0] for line in lines if line.strip().endswith("device")]


def ensure_device(sdk: Path, adb: Path) -> None:
    if connected_devices(adb):
        return
    ensure_avd(sdk)
    log_path = PACKAGE_DIR / ".build/device-lab-emulator.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log(f"booting {AVD_NAME} (emulator log: {log_path})")
    with log_path.open("w") as emulator_log:
        subprocess.Popen(
            [str(sdk / "emulator/emulator"), "-avd", AVD_NAME, "-gpu", "swiftshader_indirect", "-no-snapshot-save"],
            stdout=emulator_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    run([adb, "wait-for-device"], check=True)
    deadline = time.monotonic() + 300
    while output([adb, "shell", "getprop", "sys.boot_completed"]) != "1":
        if time.monotonic() > deadline:
            die("the emulator did not finish booting in 5 minutes")
        time.sleep(2)
    log("emulator booted")


# ---------------------------------------------------------------------------
# Build and run
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build Device Lab (Demo/) and run it on an emulator or a connected device."
    )
    parser.add_argument("--logcat", action="store_true", help="follow the app's log after launching")
    parser.add_argument("--release", action="store_true", help="build the Swift side in release")
    args = parser.parse_args()

    if not swift_android_sdk_installed():
        die(
            "the Swift Android SDK is not installed. Install it (swift.org/install), e.g.\n"
            "  swift sdk install https://download.swift.org/swift-6.3.3-release/android-sdk/"
            "swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz \\\n"
            "    --checksum d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5\n"
            "then link it to the NDK:\n"
            "  ANDROID_NDK_HOME=<sdk>/ndk/27.3.13750724 ~/Library/org.swift.swiftpm/swift-sdks/"
            "swift-6.3.3-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh"
        )

    sdk = android_sdk()
    adb = sdk / "platform-tools/adb"
    env = dict(os.environ, ANDROID_HOME=str(sdk))

    ensure_device(sdk, adb)
    abi = output([adb, "shell", "getprop", "ro.product.cpu.abi"])
    log(f"device ABI: {abi}")

    gradle = [
        DEMO_DIR / "gradlew",
        ":app:installDebug",
        f"-Pswift.abis={abi}",
        f"-Pswift.config={'release' if args.release else 'debug'}",
        "--console=plain",
    ]
    log("building and installing")
    run(gradle, cwd=DEMO_DIR, env=env, check=True)

    log("launching")
    run([adb, "shell", "am", "start", "-n", f"{APP_ID}/.MainActivity"], check=True)

    if args.logcat:
        pid = ""
        for _ in range(20):
            pid = output([adb, "shell", "pidof", APP_ID])
            if pid:
                break
            time.sleep(0.5)
        if not pid:
            die("the app is not running; see `adb logcat` for why")
        log(f"following logcat for pid {pid} (Ctrl-C to stop)")
        try:
            run([adb, "logcat", f"--pid={pid}"])
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
