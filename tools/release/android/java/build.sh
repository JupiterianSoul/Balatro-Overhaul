#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sdk="${ANDROID_HOME:-$HOME/Android/Sdk}"
jar="$(ls "$sdk"/platforms/android-*/android.jar | sort -V | tail -1)"
d8="$(command -v d8 || ls "$sdk"/build-tools/*/d8 | sort -V | tail -1)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/stub" "$work/classes" "$work/dex"
javac -nowarn --release 8 -d "$work/stub" -cp "$jar" $(find "$here/stub" -name '*.java')
javac -nowarn --release 8 -d "$work/classes" -cp "$jar:$work/stub" $(find "$here/src" -name '*.java')
"$d8" --min-api 21 --lib "$jar" --classpath "$work/stub" --output "$work/dex" $(find "$work/classes" -name '*.class')
(cd "$work/dex" && zip -q ../bridge.apk classes.dex)
apktool d -q -f -o "$work/dec" "$work/bridge.apk" >/dev/null
out="$here/../smali/org/love2d/android"
cp "$work/dec/smali/org/love2d/android/Overhaul"*.smali "$out/"
ls "$out"
