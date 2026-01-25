#!/bin/bash

# Vanta Speech Test Runner
# Usage: ./run_tests.sh [ios|android|all]

PLATFORM=${1:-all}
ROOT_DIR=$(pwd)

echo "🧪 Starting Test Suite..."

# Android Tests
if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
    echo "----------------------------------------"
    echo "🤖 Running Android Unit Tests..."
    cd "$ROOT_DIR/Vanta Sppech Android" || { echo "❌ Android directory not found!"; exit 1; }
    
    if ./gradlew testDebugUnitTest; then
        echo "✅ Android Tests Passed."
    else
        echo "❌ Android Tests Failed."
    fi
fi

# iOS Tests
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    echo "----------------------------------------"
    echo "🍎 Running iOS Unit Tests..."
    cd "$ROOT_DIR/Vanta Speech iOS" || { echo "❌ iOS directory not found!"; exit 1; }
    
    # Using 'platform=iOS Simulator' to ensure it runs without a real device
    if xcodebuild test -scheme "Vanta Speech" -destination 'platform=iOS Simulator,name=iPhone 15' -quiet; then
        echo "✅ iOS Tests Passed."
    else
        echo "❌ iOS Tests Failed."
    fi
fi

echo "----------------------------------------"
echo "🏁 Test Suite Execution Complete."
