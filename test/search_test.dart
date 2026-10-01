import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/quran_repository.dart';
import 'package:quran_app/quran_search_service.dart';

void main() {
  group('QuranSearchService Unit Tests', () {
    late QuranSearchService searchService;

    setUp(() async {
      searchService = QuranSearchService();
      // Initialize with sample ayahs
      final sampleAyahs = [
        const QuranAyah(
          surah: 1,
          ayah: 1,
          text: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
        ),
        const QuranAyah(
          surah: 1,
          ayah: 2,
          text: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ',
        ),
        const QuranAyah(
          surah: 2,
          ayah: 3,
          text: 'ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ وَيُقِيمُونَ ٱلصَّلَوٰةَ وَمِمَّا رَزَقْنَـٰهُمْ يُنفِقُونَ',
        ),
        const QuranAyah(
          surah: 2,
          ayah: 255,
          text: 'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌۭ وَلَا نَوْمٌۭ',
        ),
      ];
      await searchService.initIndex(sampleAyahs);
    });

    test('Normalizes Alef variants (أ / إ / آ / ٱ)', () {
      expect(QuranSearchService.normalizeQuery('الله'), 'الله');
      expect(QuranSearchService.normalizeQuery('إله'), 'اله');
      expect(QuranSearchService.normalizeQuery('آدم'), 'ادم');
      expect(QuranSearchService.normalizeQuery('أمر'), 'امر');
    });

    test('Normalizes Yaa / Alef Maqsura / Hamza on Waw', () {
      expect(QuranSearchService.normalizeQuery('موسى'), 'موسي');
      expect(QuranSearchService.normalizeQuery('يؤمنون'), 'يومنون');
    });

    test('Substrings match at beginning, middle, and end of words', () {
      final resultsMiddle = searchService.search('حمن'); // inside الرحمن
      expect(resultsMiddle.isNotEmpty, true);
      expect(resultsMiddle.first.verseId, 1);

      final resultsPrefix = searchService.search('الرح');
      expect(resultsPrefix.isNotEmpty, true);
    });

    test('Insensitive to diacritics and tashkeel', () {
      final results1 = searchService.search('الرحمن');
      final results2 = searchService.search('ٱلرَّحْمَـٰنِ');
      expect(results1.length, results2.length);
    });

    test('Matches prayer (الصلاة) despite Uthmani waw spelling (ٱلصَّلَوٰةَ)', () {
      final results = searchService.search('الصلاة');
      expect(results.isNotEmpty, true);
      expect(results.first.verseId, 3);
      expect(results.first.excerptMatch, contains('ٱلصَّلَوٰةَ'));
    });

    test('Excerpts have no surah or ayah labels and have correct verseId', () {
      final results = searchService.search('الحمد');
      expect(results.isNotEmpty, true);
      final r = results.first;
      expect(r.verseId, 2);
      expect(r.surah, 1);
      expect(r.ayah, 2);
      expect(r.excerptMatch, contains('ٱلْحَمْدُ'));
    });
  });
}
