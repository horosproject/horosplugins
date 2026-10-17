# JPEG to DICOM (Apple Silicon)

Native **arm64** replacement for the *JPEG to DICOM* plugin, for **Horos 4** on Apple Silicon Macs. The original plugin in [`JPEG to DICOM`](../JPEG%20to%20DICOM) only ships an x86_64 binary and doesn't load in the arm64-only Horos 4.

Maintained at **https://github.com/bersonzini-glitch/horos-imagen-a-dicom** (issues, releases and a ready-to-install `.zip`).

## Features

- Converts JPG / PNG / HEIC (anything macOS reads) to DICOM Secondary Capture and imports it into the Horos database.
- Can reuse the patient selected in the browser (read from the original DICOM header) and optionally add the images to the selected study as a new series.
- EXIF orientation, optional downsizing + JPEG Baseline, UTF-8 names.

## Build

No Xcode project needed, only the Command Line Tools:

```bash
./build.sh   # → build/JPEGToDICOMArm.horosplugin
```

It links against the Horos executable with `-bundle_loader` and an ad-hoc signature (Horos 4 has `disable-library-validation`).

The UI is in Spanish (menu: *Imagen a DICOM…*).

MIT licensed, © 2026 Bernardo Sonzini Astudillo — [columna-spine.com](https://columna-spine.com).
