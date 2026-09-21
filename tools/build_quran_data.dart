import 'dart:convert';
import 'dart:io';

const sourcePath = 'assets/quran/source/quran-uthmani.txt';
const outputPath = 'assets/quran/data/quran_data.json';

const ayahCounts = [
  7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
  123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
  112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
  34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
  54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
  60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
  14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
  28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
  29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
  15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
  11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
  5, 4, 5, 6
];

void main() {
  final source = File(sourcePath);

  if (!source.existsSync()) {
    stderr.writeln('ERROR: Tanzil source not found.');
    exit(1);
  }

  final lines = utf8
      .decode(source.readAsBytesSync())
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
      .toList();

  final expectedCount =
      ayahCounts.fold<int>(0, (sum, count) => sum + count);

  if (lines.length != expectedCount) {
    stderr.writeln(
      'ERROR: Expected $expectedCount ayahs, found ${lines.length}.',
    );
    exit(1);
  }

  final data = <Map<String, dynamic>>[];

  var index = 0;

  for (var surah = 1; surah <= ayahCounts.length; surah++) {
    for (var ayah = 1; ayah <= ayahCounts[surah - 1]; ayah++) {
      data.add({
        'surah': surah,
        'ayah': ayah,
        'text': lines[index],
      });

      index++;
    }
  }

  final output = File(outputPath);
  output.parent.createSync(recursive: true);

  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data),
    encoding: utf8,
  );

  print('SUCCESS');
  print('Ayahs: ${data.length}');
  print('Output: $outputPath');
}