#!/data/data/com.termux/files/usr/bin/bash
# Install/update OMP for Termux using the latest public Android ARM64 release asset.
#
#   curl -fsSL https://raw.githubusercontent.com/Agus27712/oh-my-pi-android/android/termux/scripts/termux/update-omp.sh | bash
#   curl -fsSL <script-url> | OMP_FORCE=1 bash
#
# Requires: bun, curl, unzip. Install with: pkg install bun curl unzip
set -euo pipefail

REPO="${OMP_FORK:-Agus27712/oh-my-pi-android}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLOBAL="$PREFIX/install/global/node_modules"
NATIVES="$GLOBAL/@oh-my-pi/pi-natives/native"

for cmd in bun curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "!! $cmd is required. Run: pkg install bun curl unzip"
    exit 1
  }
done

ARCH="$(bun -e 'console.log(process.arch)')"
[ "$ARCH" = "arm64" ] || {
  echo "!! Unsupported architecture: $ARCH (expected arm64)"
  exit 1
}

echo "== 1/5 find latest public Android ARM64 release =="
RELEASES="$(curl -fsSL --retry 3 --connect-timeout 15 \
  "https://api.github.com/repos/$REPO/releases?per_page=30")"
ASSET_URL="$(printf '%s' "$RELEASES" | bun -e '
  const releases = JSON.parse(await Bun.stdin.text());
  const release = releases.find(r => r.tag_name?.startsWith("android-arm64-") &&
    r.assets?.some(a => a.name === "pi_natives.android-arm64.node") &&
    r.assets?.some(a => a.name === "version.txt"));
  const asset = release?.assets?.find(a => a.name === "pi_natives.android-arm64.node");
  console.log(asset?.browser_download_url ?? "");
')"
VERSION_URL="$(printf '%s' "$RELEASES" | bun -e '
  const releases = JSON.parse(await Bun.stdin.text());
  const release = releases.find(r => r.tag_name?.startsWith("android-arm64-") &&
    r.assets?.some(a => a.name === "version.txt"));
  console.log(release?.assets?.find(a => a.name === "version.txt")?.browser_download_url ?? "");
')"
[ -n "$ASSET_URL" ] && [ -n "$VERSION_URL" ] || {
  echo "!! no public Android ARM64 release found."
  echo "Wait for the Android ARM64 workflow to finish successfully."
  exit 2
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== 2/5 download native addon (public release asset) =="
curl -fL --retry 3 --connect-timeout 15 "$ASSET_URL" -o "$TMP/pi_natives.android-arm64.node"
curl -fL --retry 3 --connect-timeout 15 "$VERSION_URL" -o "$TMP/version.txt"
ADDON="$TMP/pi_natives.android-arm64.node"
VERSION="$(tr -d '\r\n' < "$TMP/version.txt")"
[ -s "$ADDON" ] || { echo "!! addon download is empty"; exit 1; }
[ -n "$VERSION" ] || { echo "!! package version missing"; exit 1; }
echo "OMP version: $VERSION"

echo "== 3/5 install OMP CLI@$VERSION =="
if [ "${OMP_FORCE:-0}" = "1" ]; then
  rm -f "$PREFIX/bin/omp"
fi
BUN_INSTALL="$PREFIX" bun add -g --backend=copyfile "@oh-my-pi/pi-coding-agent@$VERSION"

echo "== 4/5 install Android addon and enable Android loader =="
[ -d "$NATIVES" ] || { echo "!! unexpected Bun install layout: $NATIVES"; exit 1; }
install -m 755 "$ADDON" "$NATIVES/pi_natives.android-arm64.node"
LOADER="$NATIVES/loader-state.js"
[ -f "$LOADER" ] || { echo "!! native loader not found: $LOADER"; exit 1; }
if ! grep -q '"android-arm64"' "$LOADER"; then
  sed -i 's/const SUPPORTED_PLATFORMS = \[/const SUPPORTED_PLATFORMS = ["android-arm64", /' "$LOADER"
fi
grep -q '"android-arm64"' "$LOADER" || { echo "!! failed to patch Android platform support"; exit 1; }

echo "== 5/5 verify installation =="
"$PREFIX/bin/omp" --version
bun -e 'const a=require(process.argv[1]); if(typeof a.countTokens!=="function") process.exit(1); console.log("native addon loaded; exports:",Object.keys(a).length)' \
  "$NATIVES/pi_natives.android-arm64.node"

echo "OK: OMP $VERSION installed for Termux ARM64."
echo "Run: omp"
