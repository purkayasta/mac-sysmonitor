#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/ModuleCache
swiftc -swift-version 6 -module-cache-path .build/ModuleCache \
    Sources/SysMon/AppRemoval.swift Tests/AppRemovalTests.swift \
    -o .build/app-removal-tests
.build/app-removal-tests
