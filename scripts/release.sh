#!/bin/bash
# Builds a Developer ID signed, notarized Macfin into dist/Macfin-<version>.zip, ready for a GitHub
# release and the Homebrew cask. Needs Config/Local.xcconfig with a Developer ID identity, and a
# notarytool keychain profile (NOTARY_PROFILE, default "tbd-notary"; see `xcrun notarytool store-credentials`).
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-tbd-notary}"
[ -f Config/Local.xcconfig ] || { echo "Config/Local.xcconfig with a Developer ID identity is required."; exit 1; }
version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml)

xcodegen generate
# Generic destination: a universal app (Apple silicon and Intel), not just this Mac's architecture
xcodebuild -project Macfin.xcodeproj -scheme Macfin -configuration Release -derivedDataPath build/release \
  -destination 'generic/platform=macOS' clean build | xcbeautify | tail -5
app=build/release/Build/Products/Release/Macfin.app
# Captured first: with pipefail, grep -q closing the pipe early would read as a failure
signature=$(codesign -dv --verbose=2 "$app" 2>&1)
grep -q "Authority=Developer ID Application" <<<"$signature" \
  || { echo "The app isn't signed with a Developer ID: check Config/Local.xcconfig."; exit 1; }

mkdir -p dist
zip="dist/Macfin-$version.zip"
rm -f "$zip"
# ditto, not zip: it keeps the signature and extended attributes
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait | tee dist/notarize.log
grep -q "status: Accepted" dist/notarize.log || { echo "Notarization refused (see dist/notarize.log)."; exit 1; }
# Staple the ticket to the app, then zip it again so it opens offline too
xcrun stapler staple "$app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "Built $zip"
shasum -a 256 "$zip"
