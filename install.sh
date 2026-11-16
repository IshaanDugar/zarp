#!/bin/bash
# Zarp installer for macOS (Apple Silicon).   Usage (Terminal):  curl -fsSL https://ishaandugar.github.io/zarp/install.sh | bash
# Reads the latest release manifest from GitHub and downloads the Mac app (a zip).
# Checks its size and SHA-256 against the manifest, puts Zarp in Applications and opens it. Nothing else.
set -euo pipefail

MANIFEST_URL="https://github.com/IshaanDugar/zarp/releases/latest/download/manifest.json"
SITE_URL="https://ishaandugar.github.io/zarp/"
APP="Zarp.app"

say() { printf '  %s\n' "$*"; }
fail() { printf '  \033[31m%s\033[0m\n' "$*" >&2; exit 1; }

printf '\n  \033[33mzarp.\033[0m  getting the latest version...\n'

[ "$(uname -s)" = "Darwin" ] || fail "This installer is for macOS. On Windows, use the PowerShell line on the page."
[ "$(uname -m)" = "arm64" ] || fail "Zarp for Mac needs an Apple Silicon Mac (M1 or newer). Intel Macs aren't supported yet, sorry."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$MANIFEST_URL" -o "$TMP/manifest.json" || fail "Couldn't reach GitHub. Check your connection and try again."

# Read the manifest with the JavaScript engine that ships with macOS (no extra tools needed).
# Prints five lines: ended (true/false), version, url, sha256, size. Empty lines for missing fields.
cat >"$TMP/read.js" <<'JXA'
function run(argv) {
  var text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, $()).js;
  var p = (JSON.parse(text) || {}).payload || {};
  var m = p.mac || {};
  return [p.beta_ended === true ? 'true' : 'false', p.latest || '', m.url || '', m.sha256 || '', m.size === undefined ? '' : String(m.size)].join(String.fromCharCode(10));
}
JXA
fields="$(osascript -l JavaScript "$TMP/read.js" "$TMP/manifest.json" 2>/dev/null || true)"
[ -n "$fields" ] || fail "Couldn't read the release information. Try again in a minute."
{ IFS= read -r ended; IFS= read -r version; IFS= read -r url; IFS= read -r want; IFS= read -r size; } <<<"$fields" || true

if [ "$ended" = "true" ]; then
  fail "This release is no longer offered. See $SITE_URL for the current one."
fi
if [ -z "${url:-}" ] || [ -z "${want:-}" ]; then
  fail "There is no Mac download in the latest release yet. See $SITE_URL"
fi
case "$url" in
  https://*) ;;
  *) fail "The download address isn't https, so I stopped. Nothing was installed. Please tell us at https://github.com/IshaanDugar/zarp/issues" ;;
esac
case "${size:-}" in
  ''|*[!0-9]*) fail "The release information has no valid size, so I stopped. Nothing was installed." ;;
esac

ZIP="$TMP/Zarp-mac.zip"
say "downloading version $version ($(( size / 1048576 )) MB)..."
curl -fsSL "$url" -o "$ZIP" || fail "The download failed. Check your connection and try again."

have_size="$(stat -f%z "$ZIP")"
[ "$have_size" = "$size" ] || fail "The download is the wrong size, so I stopped. Nothing was installed. Try again in a minute."

want="$(printf '%s' "$want" | tr 'A-F' 'a-f')"
have="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
[ "$want" = "$have" ] || fail "The download doesn't match the published checksum, so I stopped. Nothing was installed. If it keeps happening: https://github.com/IshaanDugar/zarp/issues"
say "checksum matches. installing..."

ditto -x -k "$ZIP" "$TMP/unzipped"
[ -d "$TMP/unzipped/$APP" ] || fail "The download didn't contain the app. Please tell us at https://github.com/IshaanDugar/zarp/issues"

DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

# Quit a running copy first so it can be replaced.
osascript -e 'tell application "Zarp" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "${DEST:?}/$APP"
ditto "$TMP/unzipped/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

open "$DEST/$APP"

printf '\n  \033[33minstalled in %s.\033[0m the Zarp setup window opens in a few seconds:\n' "$DEST"
say "pick the folders your notes live in, press Start, then restart your AI app once (Cmd+Q, then open it again)."
say "(already set up? then it just updated, and it is in your menu bar.)"
printf '\n'
say "anything feel off? https://github.com/IshaanDugar/zarp/issues"
printf '\n'
