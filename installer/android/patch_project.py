#!/usr/bin/env python3
"""`flutter create` yaratgan Android loyihasini CORE uchun sozlaydi.

Foydalanish (loyiha ildizidan):  python3 installer/android/patch_project.py [admin]

Asosiy ilova uchun:
  - nom (CORE), ruxsatlar, fon xizmati, qabul qilgich, PiP, cleartext HTTP
  - installer/android/kotlin/*.kt -> MainActivity va native qatlam
  - belgilar (installer/icons/android/main)
Admin ilovasi (argument `admin`) uchun faqat nom va belgi.
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(".")
HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
admin = len(sys.argv) > 1 and sys.argv[1] == "admin"


def fail(msg):
    print("XATO:", msg)
    sys.exit(1)


manifest = MANIFEST.read_text(encoding="utf-8")

# ---- nom
label = "CORE Admin" if admin else "CORE"
manifest, n = re.subn(r'android:label="[^"]*"', f'android:label="{label}"', manifest, count=1)
if n != 1:
    fail("android:label topilmadi")

# ---- qo'llab-quvvatlash raqamini ochish uchun (tel: havolasi)
queries = """<queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="tel"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>"""
if "<queries>" in manifest:
    manifest = manifest.replace("<queries>", queries, 1)

permissions = ["android.permission.INTERNET"] if admin else [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.READ_EXTERNAL_STORAGE",
        "android.permission.WRITE_EXTERNAL_STORAGE",
        "android.permission.READ_MEDIA_VIDEO",
        "android.permission.READ_MEDIA_AUDIO",
        "android.permission.READ_MEDIA_IMAGES",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
        "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
        "android.permission.WAKE_LOCK",
        "android.permission.ACCESS_WIFI_STATE",
    ]
perm_xml = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in permissions)
manifest = manifest.replace("<application", perm_xml + "    <application", 1)

if not admin:
    # <application ...> ga: HTTP havolalardan ham yuklash uchun
    manifest = re.sub(r"<application\b", '<application\n        android:usesCleartextTraffic="true"', manifest, count=1)
    # <activity ...> ga: qalqib chiquvchi oyna (PiP)
    manifest = re.sub(
        r"<activity\b",
        '<activity\n            android:supportsPictureInPicture="true"\n            android:resizeableActivity="true"',
        manifest,
        count=1,
    )
    components = """
        <service
            android:name=".CoreService"
            android:exported="false"
            android:foregroundServiceType="dataSync|mediaPlayback" />
        <receiver
            android:name=".CoreReceiver"
            android:exported="false" />
"""
    if "</application>" not in manifest:
        fail("</application> topilmadi")
    manifest = manifest.replace("</application>", components + "    </application>", 1)

MANIFEST.write_text(manifest, encoding="utf-8")

# ---- Kotlin native qatlam va bildirishnoma belgisi (faqat asosiy ilova)
if not admin:
    kt_dirs = list((ROOT / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
    if len(kt_dirs) != 1:
        fail(f"MainActivity.kt bitta bo'lishi kerak, topildi: {kt_dirs}")
    target = kt_dirs[0].parent
    package = None
    for line in kt_dirs[0].read_text(encoding="utf-8").splitlines():
        if line.startswith("package "):
            package = line.split()[1]
            break
    if not package:
        fail("MainActivity.kt ichida package yo'q")
    for src in sorted((HERE / "kotlin").glob("*.kt")):
        text = src.read_text(encoding="utf-8")
        text = re.sub(r"^package .*$", f"package {package}", text, count=1, flags=re.M)
        (target / src.name).write_text(text, encoding="utf-8")
        print("Kotlin:", target / src.name)
    res = ROOT / "android/app/src/main/res"
    shutil.copytree(HERE / "res", res, dirs_exist_ok=True)

# ---- minSdk 24 (ffmpeg va media_kit talabi)
for name in ("build.gradle", "build.gradle.kts"):
    f = ROOT / "android/app" / name
    if f.exists():
        t = f.read_text(encoding="utf-8")
        t = t.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 24").replace(
            "minSdk = flutter.minSdkVersion", "minSdk = 24"
        )
        f.write_text(t, encoding="utf-8")

# ---- ilova belgisi
icons = HERE.parent / "icons/android" / ("admin" if admin else "main")
shutil.copytree(icons, ROOT / "android/app/src/main/res", dirs_exist_ok=True)

print(MANIFEST.read_text(encoding="utf-8"))
