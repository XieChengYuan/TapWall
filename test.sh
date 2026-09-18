#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tapwall-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
export TAPWALL_APP_PATH="$TEST_DIR/TapWall.app"
bash build.sh
"$TAPWALL_APP_PATH/Contents/MacOS/TapWall" --verify
swift Tests/MakeFixture.swift "$TEST_DIR/fixture.mov"
swiftc -swift-version 5 Sources/Models.swift Sources/DefaultExample.swift Sources/VideoSession.swift Tests/VideoChecks.swift -o "$TEST_DIR/VideoChecks"
"$TEST_DIR/VideoChecks" "$TEST_DIR/fixture.mov"

swiftc -swift-version 5 Sources/DirectoryMonitor.swift Tests/DirectoryChecks.swift -o "$TEST_DIR/DirectoryChecks"
"$TEST_DIR/DirectoryChecks"

swiftc -swift-version 5 Sources/Models.swift Sources/DefaultExample.swift Sources/VideoSession.swift Tests/ExampleChecks.swift -o "$TEST_DIR/ExampleChecks"
"$TEST_DIR/ExampleChecks" "$TAPWALL_APP_PATH/Contents/Resources"

swiftc -swift-version 5 Sources/CatScene.swift Tests/CatChecks.swift -o "$TEST_DIR/CatChecks"
"$TEST_DIR/CatChecks"
