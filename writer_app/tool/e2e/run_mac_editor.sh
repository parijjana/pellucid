#!/usr/bin/env bash
# Mac editor end-to-end suite (owner's 1.1.0 checklist: Find, Settings, hidden markers, shortcuts,
# smart punctuation, paste, typewriter, new project). Same isolation and data guard as run_long_doc.sh
# (isolated .e2e bundle id, temp project, in-memory settings, mocked sync and clipboards, mtime+sha1
# guard on the owner's settings.db and ~/Documents/Musings); this only selects the test file.
#
#   tool/e2e/run_mac_editor.sh [extra flutter-test args, e.g. --plain-name "Check L60"]
#
# Waits (rechecking every 60 s) while another project's measure lock (/tmp/whimsy-measure.lock) exists.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
while [ -e /tmp/whimsy-measure.lock ]; do
  echo "whimsy measurement holds /tmp/whimsy-measure.lock; waiting 60 s..." >&2
  sleep 60
done
E2E_TEST_FILE=integration_test/mac_editor_e2e_test.dart exec "$DIR/run_long_doc.sh" "$@"
