import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:speakcards/features/practice/recorder_service.dart';
import 'package:speakcards/features/scoring/dsp_scorer.dart';

void main() {
  test('pcm roundtrip + wav header is valid, no files needed', () {
    final pcm = Uint8List(3200);
    final bd = ByteData.sublistView(pcm);
    for (var i = 0; i < 1600; i++) {
      bd.setInt16(i * 2, (i % 2 == 0 ? 1000 : -1000), Endian.little);
    }
    final floats = RecorderService.pcmToFloat32(pcm);
    expect(floats.length, 1600);
    expect(floats[0], closeTo(1000 / 32768.0, 1e-6));

    final wav = RecorderService.wavFromPcm(pcm);
    expect(wav.length, 44 + pcm.length);
    // RIFF....WAVEfmt data markers
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    final headerBd = ByteData.sublistView(wav, 0, 44);
    expect(headerBd.getUint32(24, Endian.little), 16000);
    expect(headerBd.getUint16(22, Endian.little), 1);

    // DSP accepts live PCM directly.
    expect(RecorderService.rms01(Uint8List(320)), 0.0);
    expect(RecorderService.rms01(pcm), greaterThan(0.0));

    // Stripping the synthesized header returns the original PCM path.
    final stripped = AudioPrep.pcm16FromWav(wav);
    expect(stripped.length, pcm.length);
  });
}
