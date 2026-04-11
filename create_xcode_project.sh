#!/usr/bin/env bash
# Creates the SnoreTracker Xcode project using xcodegen (if installed)
# or provides manual instructions.

set -e

echo "=== SnoreTracker Xcode Project Setup ==="

# Check for xcodegen
if command -v xcodegen &> /dev/null; then
    echo "Found xcodegen, generating project..."
    xcodegen generate
else
    echo ""
    echo "Option 1: Install xcodegen (recommended)"
    echo "  brew install xcodegen"
    echo "  Then run: xcodegen generate"
    echo ""
    echo "Option 2: Manual Xcode setup"
    echo "  1. Open Xcode → File → New → Project → iOS App"
    echo "  2. Product Name: SnoreTracker"
    echo "  3. Interface: SwiftUI, Language: Swift"
    echo "  4. Delete default ContentView.swift"
    echo "  5. Drag all .swift files from SnoreTracker/ into the project"
    echo "  6. In project settings → Info tab → add:"
    echo "     - Privacy - Microphone Usage Description"
    echo "     - Required Background Modes → App plays audio (audio)"
    echo "  7. Build & Run on a real device (mic doesn't work on simulator)"
fi
