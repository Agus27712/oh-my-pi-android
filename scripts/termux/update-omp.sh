#!/data/data/com.termux/files/usr/bin/bash
# Install/update OMP for Termux using the latest successful Android ARM64 build.
#
#   curl -fsSL https://raw.githubusercontent.com/Agus27712/oh-my-pi-android/android/termux/scripts/termux/update-omp.sh | bash
#   curl -fsSL <script-url> | OMP_FORCE=1 bash
#
# Requires: bun, curl, unzip. Install with: pkg install bun curl unzip
set -euo pipefail

REPO="${OMP_FORK:-Agus27712/oh-my-pi-android}"
BRANCH="${OMP_BRANCH:-android/termux}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLOBAL="$PREFIX/install/global/node_modules"
NATIVES="$GLOBAL/@oh-my-pi/pi-natives/native"
WORKFLOW="android-arm64-build.yml"

for cmd in bun curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "!! $cmd is required. Run: pkg install bun curl unzip"
    exit 1
  }
done

echo "== 1/5 find latest successful Android build =="
RUN_JSON="$(curl -fsSL --retry 3 --connect-timeout 15 \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW/runs?branch=$BRANCH&status=success&per_page=1")"
RUN_ID="$(printf '%s' "$RUN_JSON" | bun -e 'const j=JSON.parse(await Bun.stdin.text()); console.log(j.workflow_runs?.[0]?.id ?? "")')"
[ -n "$RUN_ID" ] || {
  echo "!! no successful Android build found for $BRANCH"
  echo "Check: https://github.com/$REPO/actions/workflows/$WORKFLOW"
  exit 2
}
echo "workflow run: $RUN_ID"

ART_JSON="$(curl -fsSL --retry 3 --connect-timeout 15 \
  "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID/artifacts")"
ART_ID="$(printf '%s' "$ART_JSON" | bun -e 'const j=JSON.parse(await Bun.stdin.text()); const a=j.artifacts?.find(x=>x.name==="omp-android-arm64-addon" && !x.expired); console.log(a?.id ?? "")')"
[ -n "$ART_ID" ] || { echo "!! Android addon artifact missing or expired"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== 2/5 download native addon =="
curl -fL --retry 3 --connect-timeout 15 \
  "https://api.github.com/repos/$REPO/actions/artifacts/$ART_ID/zip" \
  -o "$TMP/android-addon.zip"
unzip -q "$TMP/android-addon.zip" -d "$TMP/addon"
ADDON="$TMP/addon/pi_natives.android-arm64.node"
VERSION="$(cat "$TMP/addon/version.txt")"
[ -s "$ADDON" ] || { echo "!! addon file missing in artifact"; exit 1; }
[ -n "$VERSION" ] || { echo "!! package version missing in artifact"; exit 1; }
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
