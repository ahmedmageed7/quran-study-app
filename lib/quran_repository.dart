import 'dart:convert';
import 'package:flutter/services.dart';

class QuranAyah {
  final int surah;
  final int ayah;
  final String text;

  const QuranAyah({
    required this.surah,
    required this.ayah,
    required this.text,
  });

  factory QuranAyah.fromJson(Map<String, dynamic> json) {
    return QuranAyah(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      text: json['text'] as String,
    );
  }
}

class QuranRepository {
  static const String _assetPath =
      'assets/quran/data/quran_data.json';

  Future<List<QuranAyah>> loadAyahs() async {
    final jsonString = await rootBundle.loadString(_assetPath);
    final List<dynamic> jsonData = json.decode(jsonString);

    return jsonData
        .map((item) => QuranAyah.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}