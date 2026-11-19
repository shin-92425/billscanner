#!/usr/bin/env python3
"""
One-step setup for the Bill Scanner app.

Run it from this folder:

    python setup.py          (Mac/Linux: python3 setup.py)

What it does
  1. Runs `flutter create` to generate the android/ folder (only if it is missing).
  2. Makes sure Flutter did not overwrite lib/, test/ or pubspec.yaml
     (it restores them from a backup if it did).
  3. Adds the camera permission to android/app/src/main/AndroidManifest.xml.
  4. Runs `flutter pub get`.

It is safe to run again: every step is skipped if it is already done.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KEEP = ["lib", "test", "pubspec.yaml"]          # files that are ours, not Flutter's
BACKUP = ROOT / ".setup_backup"
PERMISSION = '<uses-permission android:name="android.permission.CAMERA"/>'
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"


def run(cmd):
    print("\n> " + " ".join(cmd))
    # shell=True lets Windows find flutter.bat
    return subprocess.call(cmd, cwd=ROOT, shell=(sys.platform == "win32"))


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def backup():
    if BACKUP.exists():
        shutil.rmtree(BACKUP)
    BACKUP.mkdir()
    for name in KEEP:
        src = ROOT / name
        if src.is_dir():
            shutil.copytree(src, BACKUP / name)
        elif src.exists():
            shutil.copy2(src, BACKUP / name)


def our_files_intact():
    return ("BillScannerApp" in read(ROOT / "lib" / "main.dart")
            and "flutter_vision" in read(ROOT / "pubspec.yaml"))


def restore():
    for name in KEEP:
        dst, src = ROOT / name, BACKUP / name
        if dst.is_dir():
            shutil.rmtree(dst)
        elif dst.exists():
            dst.unlink()
        if src.is_dir():
            shutil.copytree(src, dst)
        elif src.exists():
            shutil.copy2(src, dst)


def main():
    if shutil.which("flutter") is None:
        sys.exit("Flutter was not found. Install Flutter 3.41 or newer, then check that "
                 "`flutter doctor` works in a terminal and run this script again.")
    if not our_files_intact():
        sys.exit("lib/main.dart or pubspec.yaml is not the Bill Scanner version. "
                 "Extract the zip again into a fresh folder and run this script from there.")

    # 1 + 2: android/ folder
    if MANIFEST.exists():
        print("android/ folder already exists - skipping `flutter create`.")
    else:
        backup()
        code = run(["flutter", "create", "--platforms=android",
                    "--project-name", "bill_scanner", "."])
        if code != 0:
            restore()
            sys.exit("`flutter create` failed - read the message above.")
        if not our_files_intact():
            restore()
            print("Flutter replaced some app files; restored the originals.")
        shutil.rmtree(BACKUP, ignore_errors=True)

    # 3: camera permission
    text = read(MANIFEST)
    if not text:
        sys.exit(f"Could not read {MANIFEST}. Did `flutter create` finish?")
    if "android.permission.CAMERA" in text:
        print("Camera permission already in AndroidManifest.xml.")
    elif "<application" not in text:
        sys.exit("AndroidManifest.xml looks unusual. Add this line above <application ...> yourself:\n  "
                 + PERMISSION)
    else:
        MANIFEST.write_text(text.replace("<application", PERMISSION + "\n    <application", 1),
                            encoding="utf-8")
        print("Added the camera permission to AndroidManifest.xml.")

    # 4: packages
    if run(["flutter", "pub", "get"]) != 0:
        sys.exit("`flutter pub get` failed. If it mentions an SDK version, run `flutter upgrade` "
                 "(flutter_vision needs Flutter 3.41 or newer) and try again.")

    print("\nDone. Next: train a model (see README.md, steps 2-3), copy model.tflite and "
          "labels.txt into assets/, then run:  flutter run --release")


if __name__ == "__main__":
    main()
