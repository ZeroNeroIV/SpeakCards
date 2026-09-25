"""Generate bundled Spanish reference audio for every card.

Reads assets/content/cards_es_en.json, synthesizes each card's `es` text
with a native Latin American Spanish voice (edge-tts, es-MX-DaliaNeural),
and writes 16kHz mono 16-bit WAVs to each card's `audio_path`.

The app compares the learner's attempt against these references on-device
(DTW over MFCC), so they must exist for Listen + reference scoring to work.

Usage: python tool/gen_reference_audio.py
Requires: pip install edge-tts miniaudio (network needed, one-time)
"""

import asyncio
import json
import os
import wave

import edge_tts
import miniaudio

VOICE = "es-MX-DaliaNeural"
CARDS_JSON = os.path.join("assets", "content", "cards_es_en.json")
TMP_MP3 = os.path.join(
    os.environ.get("TEMP", os.environ.get("TMPDIR", ".")),
    "speakcards_ref.mp3",
)


async def synth(text: str, out_wav: str) -> float:
    await edge_tts.Communicate(text, VOICE).save(TMP_MP3)
    decoded = miniaudio.decode_file(
        TMP_MP3,
        output_format=miniaudio.SampleFormat.SIGNED16,
        nchannels=1,
        sample_rate=16000,
    )
    assert decoded.nchannels == 1 and decoded.sample_rate == 16000
    os.makedirs(os.path.dirname(out_wav), exist_ok=True)
    with wave.open(out_wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(decoded.samples.tobytes())
    return len(decoded.samples) / 16000.0


async def main() -> None:
    with open(CARDS_JSON, encoding="utf-8") as f:
        cards = json.load(f)
    for card in cards:
        secs = await synth(card["es"], card["audio_path"])
        print(f'{card["id"]:>16}  {card["es"][:40]:<40} {secs:.1f}s')
    if os.path.exists(TMP_MP3):
        os.remove(TMP_MP3)


if __name__ == "__main__":
    asyncio.run(main())
