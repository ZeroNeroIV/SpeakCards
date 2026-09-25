import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every card has a valid 16kHz mono reference WAV', () {
    final jsonFile = File('assets/content/cards_es_en.json');
    expect(jsonFile.existsSync(), isTrue, reason: 'cards json missing');
    final cards = (jsonDecode(jsonFile.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(cards, isNotEmpty);
    for (final card in cards) {
      final path = card['audio_path'] as String;
      final wav = File(path);
      expect(wav.existsSync(), isTrue,
          reason: 'missing reference audio for ${card['id']} ($path)',);
      final bytes = wav.readAsBytesSync();
      expect(bytes.length, greaterThan(44), reason: path);
      final header = ByteData.sublistView(bytes, 0, 44);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: path);
      expect(header.getUint16(20, Endian.little), 1, reason: '$path not PCM');
      expect(header.getUint16(22, Endian.little), 1, reason: '$path not mono');
      expect(header.getUint32(24, Endian.little), 16000,
          reason: '$path not 16kHz',);
      expect(header.getUint16(34, Endian.little), 16,
          reason: '$path not 16-bit',);
      final samples = header.getUint32(40, Endian.little) ~/ 2;
      expect(samples, greaterThan(4000),
          reason: '$path suspiciously short',);
    }
  });
}
