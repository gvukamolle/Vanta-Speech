#!/bin/bash

# Vanta Speech Linter Script
# Usage: ./run_linter.sh [ios|android|all]

PLATFORM=${1:-all}
ROOT_DIR=$(pwd)

echo "🔍 Starting Linter Check..."

# Android Lint
if [[ "$PLATFORM" == "android" || "$PLATFORM" == "all" ]]; then
    echo "----------------------------------------"
    echo "🤖 Checking Android Codebase..."
    cd "$ROOT_DIR/Vanta Sppech Android" || { echo "❌ Android directory not found!"; exit 1; }
    
    # Run Gradle Lint
    if ./gradlew lintDebug; then
        echo "✅ Android Lint Passed."
    else
        echo "❌ Android Lint Failed. Check report in app/build/reports/lint-results-debug.html"
    fi
fi

# iOS Lint (Xcode Analyze)
if [[ "$PLATFORM" == "ios" || "$PLATFORM" == "all" ]]; then
    echo "----------------------------------------"
    echo "🍎 Checking iOS Codebase..."
    cd "$ROOT_DIR/Vanta Speech iOS" || { echo "❌ iOS directory not found!"; exit 1; }
    
    # Run xcodebuild analyze
    # Note: 'analyze' performs static analysis looking for leaks and logic errors
    if xcodebuild -scheme "Vanta Speech" analyze -quiet; then
        echo "✅ iOS Static Analysis Passed."
    else
        echo "❌ iOS Static Analysis Found Issues."
    fi
fi

echo "----------------------------------------"
echo "🏁 Linter Check Complete."
