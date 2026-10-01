// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const sourcePath = 'assets/quran/source/quran-uthmani.txt';
const productionPath = 'assets/quran/data/quran_data.json';
const expectedAyahCount = 6236;

const ayahCounts = [
  7,
  286,
  200,
  176,
  120,
  165,
  206,
  75,
  129,
  109,
  123,
  111,
  43,
  52,
  99,
  128,
  111,
  110,
  98,
  135,
  112,
  78,
  118,
  64,
  77,
  227,
  93,
  88,
  69,
  60,
  34,
  30,
  73,
  54,
  45,
  83,
  182,
  88,
  75,
  85,
  54,
  53,
  89,
  59,
  37,
  35,
  38,
  29,
  18,
  45,
  60,
  49,
  62,
  55,
  78,
  96,
  29,
  22,
  24,
  13,
  14,
  11,
  11,
  18,
  12,
  12,
  30,
  52,
  52,
  44,
  28,
  28,
  20,
  56,
  40,
  31,
  50,
  40,
  46,
  42,
  29,
  19,
  36,
  25,
  22,
  17,
  19,
  26,
  30,
  20,
  15,
  21,
  11,
  8,
  8,
  19,
  5,
  8,
  8,
  11,
  11,
  8,
  3,
  9,
  5,
  4,
  7,
  3,
  6,
  3,
  5,
  4,
  5,
  6,
];

Never fail(String message) {
  stderr.writeln('FAIL: $message');
  exit(1);
}

void main() {
  final sourceFile = File(sourcePath);
  final productionFile = File(productionPath);

  if (!sourceFile.existsSync()) {
    fail('Source file not found: $sourcePath');
  }
  if (!productionFile.existsSync()) {
    fail('Production file not found: $productionPath');
  }

  final sourceLines = utf8
      .decode(sourceFile.readAsBytesSync())
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .where((line) => !line.trimLeft().startsWith('#'))
      .toList(growable: false);

  if (sourceLines.length != expectedAyahCount) {
    fail(
      'Immutable source contains ${sourceLines.length} verses; '
      'expected $expectedAyahCount.',
    );
  }

  final decoded = jsonDecode(utf8.decode(productionFile.readAsBytesSync()));
  if (decoded is! List) {
    fail('Production data must be a JSON list.');
  }
  if (decoded.length != expectedAyahCount) {
    fail(
      'Production data contains ${decoded.length} verses; '
      'expected $expectedAyahCount.',
    );
  }

  var index = 0;
  for (var surah = 1; surah <= ayahCounts.length; surah++) {
    for (var ayah = 1; ayah <= ayahCounts[surah - 1]; ayah++) {
      final record = decoded[index];
      if (record is! Map<String, dynamic>) {
        fail('Record ${index + 1} is not a JSON object.');
      }

      if (record['surah'] != surah || record['ayah'] != ayah) {
        fail(
          'Record ${index + 1} has location '
          '${record['surah']}:${record['ayah']}; expected $surah:$ayah.',
        );
      }

      final productionText = record['text'];
      if (productionText is! String) {
        fail('Record $surah:$ayah has no text string.');
      }
      if (productionText != sourceLines[index]) {
        fail(
          'Production text differs from the immutable source at $surah:$ayah.',
        );
      }

      index++;
    }
  }

  if (index != expectedAyahCount) {
    fail('Validated $index verses; expected $expectedAyahCount.');
  }

  print('PASS: production Quran data matches the immutable source exactly.');
  print('Surahs: ${ayahCounts.length}');
  print('Ayahs: $index');
}
