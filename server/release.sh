#!/bin/zsh
# Publishes the app build that is in ~/attendance-planner to the download link
# and tells installed apps about it.
#
#   ./release.sh "What is new, in one short sentence"
#
# Build the APK first (flutter build apk --release --split-per-abi).
set -e
here=${0:A:h}
app=$HOME/attendance-planner
apk=$app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
line=$(grep '^version:' $app/pubspec.yaml)            # version: 1.4.0+5
version=${${line#version: }%+*}
build=${line#*+}
[[ -f $apk ]] || { echo "No APK at $apk"; exit 1; }
cp $apk $app/IIMM-Buddy.apk
cp $apk $here/public/IIMM-Buddy.apk
sha=$(shasum -a 256 $apk | cut -d' ' -f1)
size=$(stat -f%z $apk)
NOTES="${1:-}" python3 - "$here/public/version.json" "$build" "$version" "$sha" "$size" <<'PY'
import json, os, sys
path, build, version, sha, size = sys.argv[1:6]
json.dump({'build': int(build), 'version': version, 'notes': os.environ.get('NOTES', ''),
           'apk': '/IIMM-Buddy.apk', 'sha256': sha, 'size': int(size)}, open(path, 'w'), indent=2)
PY
mb=$(( (size + 500000) / 1000000 ))
sed -i '' -E "s/Version [0-9.]+ · [0-9]+ MB/Version $version · $mb MB/" $here/public/index.html
cd $here && vercel deploy --prod --yes 2>&1 | grep -E "Aliased|Error" | head -3
# Tell phones with push to look for the update now.
sleep 5
curl -s -m 30 -X POST "https://buddy.iimmumbai.in/api/poke?type=update" \
  -H "Authorization: Bearer $(tr -d '\n' < $here/publisher-key.txt)" | cut -c1-80; echo
echo "Published $version (build $build), $mb MB"
