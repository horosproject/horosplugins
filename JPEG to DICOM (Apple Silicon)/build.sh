#!/bin/zsh
# Builds JPEGToDICOMArm.horosplugin (arm64) and the jpg2dcm_test CLI.
set -euo pipefail
cd "${0:A:h}"

HOROS=/Applications/Horos.app/Contents/MacOS/Horos
OUT=build/JPEGToDICOMArm.horosplugin
FLAGS=(-arch arm64 -fobjc-arc -O2 -mmacosx-version-min=11.0 -Wall)

rm -rf build
mkdir -p "$OUT/Contents/MacOS"
cp Info.plist "$OUT/Contents/Info.plist"

clang "${FLAGS[@]}" -bundle -bundle_loader "$HOROS" \
  -framework Cocoa -framework ImageIO -framework UniformTypeIdentifiers \
  JPEGToDICOMArm.m DicomWriter.m DicomHeaderReader.m -o "$OUT/Contents/MacOS/JPEGToDICOMArm"

codesign --force --sign - "$OUT"

clang "${FLAGS[@]}" -framework Foundation -framework ImageIO -framework CoreGraphics \
  test_main.m DicomWriter.m DicomHeaderReader.m -o build/jpg2dcm_test

(cd build && ditto -c -k --keepParent JPEGToDICOMArm.horosplugin JPEGToDICOMArm.horosplugin.zip)

echo "Built $OUT"
