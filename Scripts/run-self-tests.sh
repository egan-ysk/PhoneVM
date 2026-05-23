#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/self-tests"
mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/Sources/PhoneVM/Domain/VirtualMachine.swift" \
  "$ROOT_DIR/Sources/PhoneVM/Domain/VirtualMachineProvider.swift" \
  "$ROOT_DIR/Sources/PhoneVM/Infrastructure/FileManager+Directory.swift" \
  "$ROOT_DIR/Sources/PhoneVM/Infrastructure/KeyValueFileParser.swift" \
  "$ROOT_DIR/Sources/PhoneVM/Infrastructure/ProcessRunner.swift" \
  "$ROOT_DIR/Sources/PhoneVM/Infrastructure/ToolLocator.swift" \
  "$ROOT_DIR/Sources/PhoneVM/Providers/AndroidAVDProvider.swift" \
  "$ROOT_DIR/SelfTests/main.swift" \
  -o "$BUILD_DIR/PhoneVMSelfTests"

"$BUILD_DIR/PhoneVMSelfTests"
