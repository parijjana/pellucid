#!/usr/bin/env bash
# Long-document (windowed editor) end-to-end suite for the real macOS app.
#
#   tool/e2e/run_long_doc.sh [extra flutter-test args, e.g. --plain-name "Check 3"]
#
# ISOLATION
#  * The test build gets its own bundle id (com.overengineeredhobbies.pellucid.e2e) through an
#    untracked macos/Runner/Configs/E2E.xcconfig that AppInfo.xcconfig includes if present. Its
#    app-support dir and container are therefore separate from the owner's real ones.
#  * The test mounts EditorScreen over a temp directory project and an in-memory settings DB; it
#    refuses to run unless the app-support path contains the .e2e bundle id.
#  * This script never launches, quits or signals any other Pellucid process.
#  * GUARD: mtime + sha1 of the owner's settings.db and of ~/Documents/Musings are recorded before
#    and after; any difference fails the run (exit 3).
#  * Frame timing takes the /tmp/pellucid-measure.lock mkdir lock for the duration of the run.
set -u
APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$APP_DIR" || exit 2

REAL_DB="$HOME/Library/Containers/com.overengineeredhobbies.pellucid/Data/Library/Application Support/com.overengineeredhobbies.pellucid/settings.db"
MUSINGS="$HOME/Documents/Musings"
LOCK=/tmp/pellucid-measure.lock
XCFG="$APP_DIR/macos/Runner/Configs/E2E.xcconfig"
OUT="${E2E_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/pellucid-e2e-out.XXXXXX")}"
mkdir -p "$OUT"

fingerprint() { # prints mtime + sha1 for settings.db and Musings (read-only)
  if [ -f "$REAL_DB" ]; then
    echo "settings.db  mtime=$(stat -f %m "$REAL_DB")  sha1=$(shasum -a 1 < "$REAL_DB" | cut -d' ' -f1)"
  else
    echo "settings.db  (absent)"
  fi
  if [ -d "$MUSINGS" ]; then
    local listing newest
    listing="$(cd "$MUSINGS" && find . -type f -print0 | sort -z | xargs -0 shasum -a 1 2>/dev/null)"
    newest="$(cd "$MUSINGS" && find . -type f -exec stat -f %m {} + | sort -n | tail -1)"
    echo "Musings      dir-mtime=$(stat -f %m "$MUSINGS")  newest-file-mtime=$newest  files=$(echo "$listing" | wc -l | tr -d ' ')  sha1=$(echo "$listing" | shasum -a 1 | cut -d' ' -f1)"
  else
    echo "Musings      (absent)"
  fi
}

cleanup() {
  rm -f "$XCFG"          # a file this script created
  rmdir "$LOCK" 2>/dev/null
}
trap cleanup EXIT

if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Another measurement holds $LOCK; refusing to run." >&2
  exit 4
fi

BEFORE="$(fingerprint)"
echo "=== GUARD before ==="; echo "$BEFORE"

cat > "$XCFG" <<'XC'
PRODUCT_BUNDLE_IDENTIFIER = com.overengineeredhobbies.pellucid.e2e
PRODUCT_NAME = PellucidE2E
XC

echo "=== flutter test (build + run) ==="
flutter test "${E2E_TEST_FILE:-integration_test/long_doc_e2e_test.dart}" -d macos --machine "$@" > "$OUT/machine.jsonl" 2> "$OUT/stderr.log"
RC=$?
echo "flutter test exit code: $RC   (raw output: $OUT)"

AFTER="$(fingerprint)"
echo "=== GUARD after ==="; echo "$AFTER"
GUARD=PASS
if [ "$BEFORE" != "$AFTER" ]; then
  GUARD=FAIL
  echo "!!! GUARD FAILED: owner data fingerprints differ (see before/after above)." >&2
else
  echo "GUARD OK: settings.db and ~/Documents/Musings unchanged (mtime and sha1)."
fi

python3 "$APP_DIR/tool/e2e/summarize.py" "$OUT/machine.jsonl" "$OUT/stderr.log"
SRC=$?
[ "$GUARD" = FAIL ] && exit 3
[ $RC -ne 0 ] && exit $RC
exit $SRC
