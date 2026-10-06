#!/bin/zsh
# Targeted regressions from the production sources, without launching Damla or using live services.
set -euo pipefail
DAMLA_PROJECT_DIR="${0:A:h:h}"
DAMLA_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/Damla-regressions.XXXXXX")"
trap 'rm -rf "$DAMLA_TEST_DIR"' EXIT
cat > "$DAMLA_TEST_DIR/RegressionMain.swift" <<'SWIFT'
import Foundation

@main
struct RegressionMain {
    static func main() {
        UserDefaults.standard.setVolatileDomain(["AppleLanguages": ["tr"]], forName: UserDefaults.argumentDomain)
        var failures = 0
        for (name, tests) in [("Focus", runFocusSelfTests), ("Calendar", runCalendarSelfTests), ("Lyrics", runLyricsSelfTests)] {
            var count = 0, failed = 0
            tests { ok, description in
                count += 1
                if !ok { failed += 1; print("FAIL: \(description)") }
            }
            print("\(name) regressions: \(count - failed)/\(count) passed")
            failures += failed
        }
        exit(failures == 0 ? 0 : 1)
    }
}
SWIFT
xcrun swiftc -swift-version 5 -module-cache-path "$DAMLA_TEST_DIR/ModuleCache" \
  "$DAMLA_PROJECT_DIR/Sources/Damla/Domain.swift" \
  "$DAMLA_PROJECT_DIR/Sources/Damla/FocusSelfTests.swift" \
  "$DAMLA_PROJECT_DIR/Sources/Damla/Meetings.swift" \
  "$DAMLA_PROJECT_DIR/Sources/Damla/CalendarSelfTests.swift" \
  "$DAMLA_PROJECT_DIR/Sources/Damla/Lyrics.swift" \
  "$DAMLA_PROJECT_DIR/Sources/Damla/LyricsSelfTests.swift" \
  "$DAMLA_TEST_DIR/RegressionMain.swift" -o "$DAMLA_TEST_DIR/regressions"
"$DAMLA_TEST_DIR/regressions"
