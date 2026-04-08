#!/bin/bash

set -euo pipefail

echo ""
echo "PPTBridge SK for OBS — developer dependency helper"
echo "by Srđan Kotarlić"
echo ""

echo "This script is for building the native plugin from source."
echo "It is not required for normal end-user installation."
echo ""

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed."
  echo "Install Homebrew first from https://brew.sh and then run this script again."
  exit 1
fi

echo "[1/3] Installing LibreOffice..."
brew install --cask libreoffice

echo "[2/3] Installing CMake..."
brew install cmake

echo "[3/3] Installing SIMDe headers..."
brew install simde

echo ""
echo "Done."
echo "Next:"
echo "1. Make sure OBS is installed in /Applications/OBS.app"
echo "2. Configure the native plugin with CMake"
echo "3. Build it from native-plugin/"
echo ""
