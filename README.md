# SpeakCards — Spanish for English speakers · LAYA-only · 100% on-device

Flutter + SQLite voice flashcards. One AI (LAYA), no server, no cloud.

## Status: live mic scoring, no mocks, no WAV files

Live PCM stream → on-device DSP → LAYA → SRS. Every push builds
`app-release.apk` via GitHub Actions and publishes it as the `LATEST` release.

## Setup

```powershell
winget install Google.Flutter  # or download SDK, then:
flutter doctor
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # drift db.g.dart
flutter test
flutter run
```

Record reference WAVs (human speaker, 16kHz mono) into `assets/audio/es/`
matching `audio_path` in `assets/content/cards_es_en.json`.

## Models (download once on WiFi, stored on-device)

- Path A (LAYA hears audio): `google/gemma-3n-E2B-it` `.litertlm` + audio
  adapter via `flutter_gemma` `supportAudio:true`. Alt GGUF:
  `unsloth/gemma-3n-E2B-it-GGUF:Q4_K_M` (~2.8GB). Needs ~6GB RAM.
- Path B (DSP + text LAYA): `google/gemma-3-270m-it` (~0.3GB). Works on 4GB.
- Router: `ModelManager.deviceSupportsAudioLaya()` picks A if RAM allows,
  else B. Rule fallback if no model installed.

## What LAYA does / does not do

- DSP (`lib/features/scoring/dsp_scorer.dart`, pure Dart, NOT AI): MFCC+DTW
  distance vs bundled reference, fluency, completeness, prosody proxy.
- LAYA (only AI): takes DSP numbers (B) or raw PCM (A) + card + history →
  `{next_action, target, confidence, feedback_en, feedback_es}`.
- App computes SRS dates; LAYA picks category only.

## Honesty rule

Sentence cards show match/fluency/completeness only. No fake per-word %
or IPA-heard. Single-word drills may show overall as the word score.
