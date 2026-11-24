#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/ModuleCache
bash scripts/test-app-removal.sh
swiftc -swift-version 6 -module-cache-path .build/ModuleCache \
    Sources/SysMon/SettingsStore.swift Sources/SysMon/MetricReading.swift \
    Sources/SysMon/SystemSampler.swift Sources/SysMon/NativeSystemCounters.swift \
    Tests/SysMonTests/CollectorTests.swift -o .build/collector-tests
.build/collector-tests
swiftc -swift-version 6 -module-cache-path .build/ModuleCache \
    Sources/SysMon/AppRemoval.swift scripts/QuitRequest.swift scripts/install-built-app.swift \
    -o .build/install-built-app-tests
swiftc -parse-as-library -swift-version 6 -module-cache-path .build/ModuleCache \
    Tests/ScriptTests.swift -o .build/script-tests
.build/script-tests "$PROJECT_DIR"
swiftc -parse-as-library -swift-version 6 -module-cache-path .build/ModuleCache \
    Tests/QuitFixture.swift -o .build/quit-fixture
swiftc -swift-version 6 -module-cache-path .build/ModuleCache \
    Sources/SysMon/SettingsStore.swift Sources/SysMon/SettingsWindowController.swift \
    Sources/SysMon/StatusGraphic.swift Sources/SysMon/AppRemoval.swift Sources/SysMon/AppInstanceShutdown.swift \
    Sources/SysMon/MetricReading.swift \
    Sources/SysMon/SystemSampler.swift Sources/SysMon/NativeSystemCounters.swift \
    scripts/QuitRequest.swift Tests/ShutdownTests.swift Tests/LifecycleTests.swift \
    -o .build/lifecycle-tests
.build/lifecycle-tests --modal
LIFECYCLE_LOG="$PROJECT_DIR/.build/lifecycle-test-output.log"
if ! .build/lifecycle-tests >"$LIFECYCLE_LOG" 2>&1; then
    cat "$LIFECYCLE_LOG"
    exit 1
fi
cat "$LIFECYCLE_LOG"
# A native test process can be terminated by AppKit with exit status zero;
# require the end marker so that cannot silently skip asynchronous checks.
case "$(cat "$LIFECYCLE_LOG")" in
    *'Passed settings close/quit, native appearance, and asynchronous quit responsiveness checks.'*) ;;
    *) printf 'Lifecycle tests did not finish.\n' >&2; exit 1 ;;
esac
