#!/bin/sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

ci=0
for arg in "$@"; do
  case "$arg" in
    --ci) ci=1 ;;
    *)
      echo "Unknown option: $arg (expected --ci)" >&2
      exit 1
      ;;
  esac
done

"$root/scripts/build-app.sh"
app="$root/build/Rfred.app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
arch="$(uname -m)"
stage="$root/dist/dmg-stage"
dmg="$root/dist/Rfred-${version}-${arch}.dmg"

rm -rf "$stage" "$dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/Rfred.app"
ln -s /Applications "$stage/Applications"

cat > "$stage/Install.txt" <<'EOF'
Rfred
=====

Requires macOS 14 or later. This build is Apple Silicon (arm64) only.

1. Drag Rfred into Applications.
2. First launch: right-click Rfred.app and choose Open
   (the app is self-signed with a stable certificate, not notarized).
   Or run: xattr -cr /Applications/Rfred.app

Rfred stays out of the Dock until Preferences is open.
EOF

hdiutil create \
  -volname "Rfred" \
  -srcfolder "$stage" \
  -ov \
  -format UDZO \
  "$dmg" >/dev/null

rm -rf "$stage"

echo "Built $dmg"

if [ "$ci" = 1 ]; then
  exit 0
fi

dropbox="$HOME/Dropbox"
if [ -d "$dropbox" ]; then
  cp -f "$dmg" "$dropbox/$(basename "$dmg")"
  echo "Copied $dropbox/$(basename "$dmg")"
fi
