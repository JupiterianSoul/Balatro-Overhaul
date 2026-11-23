#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
android_sdk="${ANDROID_HOME:-$HOME/Android/Sdk}"
android_jar="$(ls "$android_sdk"/platforms/android-*/android.jar | sort -V | tail -1)"
d8_tool="$(command -v d8 || ls "$android_sdk"/build-tools/*/d8 | sort -V | tail -1)"
work_dir="$repo/.night/refresh_rate"
device_dir=/data/local/tmp/overhaul_refresh_rate

rm -rf "$work_dir"
mkdir -p "$work_dir/stub/org/love2d/android" "$work_dir/classes" "$work_dir/dex"
adb get-state >/dev/null

python3 "$here/make_apk.py" runtime --work "$work_dir" --out "$work_dir/runtime.apk" >/dev/null

cat > "$work_dir/stub/org/love2d/android/HighRefreshRate.java" <<'EOF'
package org.love2d.android;
public class HighRefreshRate {
    public static android.view.Display.Mode pickMode(android.view.Display.Mode currentMode, android.view.Display.Mode[] supportedModes) { return null; }
}
EOF
javac -nowarn --release 8 -d "$work_dir/stub" -cp "$android_jar" "$work_dir/stub/org/love2d/android/HighRefreshRate.java"
javac -nowarn --release 8 -d "$work_dir/classes" -cp "$android_jar:$work_dir/stub" "$here/java/test/org/love2d/android/HighRefreshRateTest.java"
"$d8_tool" --min-api 21 --lib "$android_jar" --classpath "$work_dir/stub" --output "$work_dir/dex" $(find "$work_dir/classes" -name '*.class')

adb shell rm -rf "$device_dir"
adb shell mkdir -p "$device_dir"
adb push -q "$work_dir/runtime.apk" "$device_dir/runtime.apk"
adb push -q "$work_dir/dex/classes.dex" "$device_dir/test.dex"
exit_status=0
adb shell "dalvikvm -cp $device_dir/runtime.apk:$device_dir/test.dex org.love2d.android.HighRefreshRateTest; echo exit=\$?" | tee "$work_dir/out.txt"
grep -q '^exit=0' "$work_dir/out.txt" || exit_status=1
adb shell rm -rf "$device_dir"
exit $exit_status
