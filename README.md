# Video Linter

A native macOS app for QC-checking video files before uploading to YouTube. Drop in one or more files and get a pass/fail report in seconds — all analysis runs locally, no network required.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What it checks

| Check | Threshold | Detail |
|---|---|---|
| **Video Bitrate** | ≥ 25 Mbps | Flags low-bitrate encodes that will look compressed on YouTube |
| **Resolution** | 2560 × 1440 | Exact QHD match required |
| **Frame Rate** | 30 or 29.97 fps | Flags any other frame rate |
| **Video Codec** | H.264 (avc1) | Flags HEVC, VP9, ProRes, etc. |
| **Duration** | warns if < 1 min | Catches accidentally truncated exports |
| **A/V Sync** | stream durations within 500 ms | Catches drift that builds up over long videos |
| **Black Frames** | no sustained black > 2 s | Reports exact timestamps so you can find the cut |
| **Audio Loudness** | ≥ −23 LUFS | Full ITU-R BS.1770-4 K-weighted integrated loudness |
| **Audio Peak** | ≤ −1 dBFS | Sample-peak scan across the entire file |
| **Complete Silence** | no gap > 2 s | Detects true flat/zero signal, not quiet room tone |

Every failed check includes a human-readable explanation. Black frames and silence gaps are timestamped (`HH:MM:SS – HH:MM:SS`) so you know exactly where to look in your editor.

## Screenshots

> Drop zone (no files loaded)

```
┌─────────────────────────────────────────────┐
│                                             │
│              ↓  Drop video files here       │
│       or click Add Files in the toolbar     │
│                  MP4 · MOV · M4V            │
│                                             │
└─────────────────────────────────────────────┘
```

> Results panel (file analysed)

```
▾ 🎬 my-video.mp4                      ● FAIL
  ✓ Video Bitrate   42.3 Mbps
  ✗ Resolution      Found 1920×1080 — expected 2560×1440
  ✓ Frame Rate      29.970 fps
  ✓ Video Codec     H.264 (avc1)
  ✓ Duration        18:42
  ✓ A/V Sync        Stream durations match (Δ 2 ms)
  ✗ Black Frames    1 sustained black frame section detected
      Black frames at 2:14 – 2:19
  ✓ Audio Loudness  −16.2 LUFS
  ✓ Audio Peak      −3.1 dBFS
  ✓ Complete Silence  No silence gaps detected
```

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (to build from source)

## Building

```bash
git clone https://github.com/ash-cortez/videolinter.git
open videolinter/Package.swift   # opens in Xcode as a SwiftPM project
```

Hit **⌘R** to build and run.

No external dependencies — everything is built on AVFoundation and SwiftUI.

## Usage

- **Drag and drop** one or more `.mp4`, `.mov`, or `.m4v` files onto the window
- Or press **⌘O** (or the Add Files button in the toolbar) to open a file picker
- Each file is analysed in the background; the UI stays responsive
- Click the chevron on any result row to expand timestamps and details
- Click **×** on a card to remove a file; **Clear All** to reset

## How the analysis works

### LUFS (loudness)
Implements the full ITU-R BS.1770-4 K-weighting chain — two cascaded biquad IIR filters (high-shelf pre-filter at 1682 Hz, then high-pass RLB filter at 38 Hz) applied per channel. Mean square is accumulated in a single streaming pass over the decoded PCM data, so even hour-long files don't spike memory.

### Black frame detection
Uses `AVAssetImageGenerator` to sample a 64 × 36 thumbnail every 500 ms. Each frame is rendered into an 8-bit grayscale context and the average luminance is calculated. Frames below 4% luminance are flagged as black; runs of 2 seconds or more are reported with start/end timestamps.

### Silence detection
Audio is read as 32-bit float linear PCM via `AVAssetReader`. Every 100 ms window is checked for RMS below −60 dBFS (amplitude ≈ 0.001). This catches true digital silence or near-zero signal without flagging normal room tone.

## License

MIT
