# Video Linter — Claude Context

## Project
**Name:** Video Linter
**Goal:** Native macOS QC tool that checks video files before uploading to YouTube. All analysis runs locally via AVFoundation — no network calls, no external dependencies.

## Tech Stack
- Swift 5.9 + SwiftUI
- macOS 13+ (Ventura)
- AVFoundation for all media analysis
- SwiftPM (no external packages)

## Supported formats
MP4, MOV, M4V

## QC Checks & Requirements

| Check | Requirement | Severity |
|---|---|---|
| Video Bitrate | ≥ 25 Mbps | Fail |
| Resolution | Exactly 2560 × 1440 | Fail |
| Frame Rate | 30 fps or 29.97 fps | Fail |
| Video Codec | H.264 (avc1) only | Fail |
| Duration | Warn if under 1 minute | Warning |
| A/V Sync | Audio/video stream durations within 500 ms | Fail |
| Black Frames | No sustained black longer than 2 seconds | Fail |
| Audio Loudness | Average ≥ −23 LUFS (BS.1770-4 K-weighted) | Fail |
| Audio Peak | No clipping above −1 dBFS | Fail |
| Complete Silence | No flat/zero signal gaps longer than 2 seconds | Fail |

Silence means true digital silence (< −60 dBFS RMS) — not quiet room tone.
Black frames use luminance < 4% average on a 64×36 thumbnail sampled every 500 ms.

## UI Requirements
- Clean, minimal native macOS feel
- Drag & drop zone or ⌘O file picker
- Results panel: expandable per-file cards
- Status indicators: green checkmark (pass), red X (fail), yellow warning
- Overall PASS / FAIL badge per file
- Progress indicator while analysing
- Timestamps on black frame and silence issues (e.g. `2:14 – 2:19`)
- Human-readable failure explanations on every failed check
- Analysis must be async — UI stays responsive at all times

## Architecture

```
AppViewModel          — @MainActor, owns report list, dispatches analysis Tasks
VideoReport           — @MainActor ObservableObject per file
VideoAnalyzer         — Orchestrator (static func), calls sub-analyzers in sequence
TrackAnalyzer         — Bitrate, resolution, fps, codec, duration, A/V sync
AudioAnalyzer         — LUFS (K-weighting biquad IIR), peak, silence gaps
BlackFrameAnalyzer    — AVAssetImageGenerator sampling + luminance check
```

Key concurrency rule: `VideoReport` is `@MainActor + @unchecked Sendable`. All mutations from background tasks go through `Task { @MainActor in }`.

Audio is read as a streaming pass via `AVAssetReader` (32-bit float linear PCM) — never buffers the entire file in memory.

## GitHub
https://github.com/ash-cortez/videolinter
