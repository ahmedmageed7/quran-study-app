import 'quran_repository.dart';

class SearchResult {
  final int verseId; // 1-indexed (1..6236)
  final int surah;
  final int ayah;
  final String uthmaniText;
  final String excerptPrefix;
  final String excerptMatch;
  final String excerptSuffix;
  final bool hasLeadingEllipsis;
  final bool hasTrailingEllipsis;

  const SearchResult({
    required this.verseId,
    required this.surah,
    required this.ayah,
    required this.uthmaniText,
    required this.excerptPrefix,
    required this.excerptMatch,
    required this.excerptSuffix,
    required this.hasLeadingEllipsis,
    required this.hasTrailingEllipsis,
  });
}

class SearchableAyah {
  final int verseId;
  final int surah;
  final int ayah;
  final String uthmaniText;
  final String normalizedText;
  final List<int> origCharIndices;

  const SearchableAyah({
    required this.verseId,
    required this.surah,
    required this.ayah,
    required this.uthmaniText,
    required this.normalizedText,
    required this.origCharIndices,
  });
}

class QuranSearchService {
  static final QuranSearchService _instance = QuranSearchService._internal();
  factory QuranSearchService() => _instance;
  QuranSearchService._internal();

  List<SearchableAyah>? _searchIndex;
  bool _isIndexing = false;

  bool get isReady => _searchIndex != null;

  /// Initializes the search index once in memory from QuranAyah records.
  Future<void> initIndex(List<QuranAyah> ayahs) async {
    if (_searchIndex != null || _isIndexing) return;
    _isIndexing = true;

    final indexList = <SearchableAyah>[];
    for (int i = 0; i < ayahs.length; i++) {
      final a = ayahs[i];
      final mapping = _normalizeWithMapping(a.text);
      indexList.add(
        SearchableAyah(
          verseId: i + 1,
          surah: a.surah,
          ayah: a.ayah,
          uthmaniText: a.text,
          normalizedText: mapping.normalized,
          origCharIndices: mapping.origIndices,
        ),
      );
    }

    _searchIndex = indexList;
    _isIndexing = false;
  }

  /// Normalizes a query entered by the user.
  static String normalizeQuery(String input) {
    var text = input;

    // 1. In Uthmani orthography waw with dagger alif represents pronounced alif (صلاة, زكاة, حياة)
    text = text.replaceAll(RegExp(r'و[\u064B-\u065F]*\u0670'), 'ا');

    // 2. Remove all Quranic stop signs and annotation marks (U+06D6 to U+06ED)
    text = text.replaceAll(RegExp(r'[\u06D6-\u06ED]'), '');

    // 3. Remove all tashkeel (harakat) and combining marks (U+064B to U+065F, U+0670, U+08D3-U+08FF)
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u08D3-\u08FF]'), '');

    // 4. Remove tatweel / kashida (U+0640)
    text = text.replaceAll('\u0640', '');

    // 5. Remove zero-width characters and bidi marks
    text = text.replaceAll(RegExp(r'[\u200B-\u200F\uFEFF]'), '');

    // 6. Normalize all Alef forms (أ, إ, آ, ٱ, ٲ, ٳ) -> ا
    text = text.replaceAll(RegExp(r'[أإآٱٲٳ]'), 'ا');

    // 7. Normalize Yaa / Alef Maqsura (ى, ئ) -> ي
    text = text.replaceAll(RegExp(r'[ىئ]'), 'ي');

    // 8. Normalize Waw with Hamza (ؤ) -> و
    text = text.replaceAll('ؤ', 'و');

    // 9. Normalize Ta Marbuta (ة) -> ه
    text = text.replaceAll('ة', 'ه');

    return text.trim();
  }

  /// Normalizes Quran text while keeping track of the original character indices.
  static _MappingResult _normalizeWithMapping(String orig) {
    final normChars = <String>[];
    final indices = <int>[];

    final isWawDagger = RegExp(r'^و[\u064B-\u065F]*\u0670');
    final isIgnored = RegExp(r'^[\u06D6-\u06ED\u064B-\u065F\u0670\u08D3-\u08FF\u0640\u200B-\u200F\uFEFF]');

    int i = 0;
    while (i < orig.length) {
      final sub = orig.substring(i);

      // Check waw with dagger alif
      final matchWaw = isWawDagger.matchAsPrefix(sub);
      if (matchWaw != null) {
        normChars.add('ا');
        indices.add(i);
        i += matchWaw.group(0)!.length;
        continue;
      }

      // Check ignored marks (tashkeel, symbols, tatweel)
      final matchIgnored = isIgnored.matchAsPrefix(sub);
      if (matchIgnored != null) {
        i += matchIgnored.group(0)!.length;
        continue;
      }

      final char = orig[i];

      // Normalize Alef variants
      if ('أإآٱٲٳ'.contains(char)) {
        normChars.add('ا');
        indices.add(i);
      } else if ('ىئ'.contains(char)) {
        normChars.add('ي');
        indices.add(i);
      } else if (char == 'ؤ') {
        normChars.add('و');
        indices.add(i);
      } else if (char == 'ة') {
        normChars.add('ه');
        indices.add(i);
      } else {
        normChars.add(char);
        indices.add(i);
      }
      i++;
    }

    return _MappingResult(normChars.join(), indices);
  }

  static bool _isCombiningMark(int codeUnit) {
    return (codeUnit >= 0x064B && codeUnit <= 0x065F) ||
        codeUnit == 0x0670 ||
        (codeUnit >= 0x06D6 && codeUnit <= 0x06ED) ||
        (codeUnit >= 0x08D3 && codeUnit <= 0x08FF);
  }

  /// Instant search matching query in start, middle, and end of words.
  List<SearchResult> search(String rawQuery) {
    final query = normalizeQuery(rawQuery);
    if (query.isEmpty || _searchIndex == null) {
      return const [];
    }

    final results = <SearchResult>[];
    final index = _searchIndex!;

    for (int i = 0; i < index.length; i++) {
      final item = index[i];
      final matchPos = item.normalizedText.indexOf(query);
      if (matchPos != -1) {
        results.add(
          _extractExcerpt(
            ayah: item,
            normMatchIndex: matchPos,
            normQueryLength: query.length,
          ),
        );
      }
    }

    return results;
  }

  static SearchResult _extractExcerpt({
    required SearchableAyah ayah,
    required int normMatchIndex,
    required int normQueryLength,
  }) {
    final orig = ayah.uthmaniText;
    final indices = ayah.origCharIndices;

    if (normMatchIndex >= indices.length) {
      return SearchResult(
        verseId: ayah.verseId,
        surah: ayah.surah,
        ayah: ayah.ayah,
        uthmaniText: orig,
        excerptPrefix: '',
        excerptMatch: orig,
        excerptSuffix: '',
        hasLeadingEllipsis: false,
        hasTrailingEllipsis: false,
      );
    }

    final startOrig = indices[normMatchIndex];
    final lastCharNormIndex = normMatchIndex + normQueryLength - 1;
    final lastCharOrig = lastCharNormIndex < indices.length
        ? indices[lastCharNormIndex]
        : indices.last;

    int endOrig = lastCharOrig + 1;
    while (endOrig < orig.length && _isCombiningMark(orig.codeUnitAt(endOrig))) {
      endOrig++;
    }

    final matchText = orig.substring(startOrig, endOrig);

    // Approximate window around match (e.g. 30 characters before and after)
    const contextChars = 30;

    int prefixStart = startOrig - contextChars;
    bool hasLeading = false;
    if (prefixStart <= 0) {
      prefixStart = 0;
    } else {
      final space = orig.indexOf(' ', prefixStart);
      if (space != -1 && space < startOrig) {
        prefixStart = space + 1;
        hasLeading = true;
      } else {
        hasLeading = true;
      }
    }
    final prefixText = orig.substring(prefixStart, startOrig);

    int suffixEnd = endOrig + contextChars;
    bool hasTrailing = false;
    if (suffixEnd >= orig.length) {
      suffixEnd = orig.length;
    } else {
      final space = orig.lastIndexOf(' ', suffixEnd);
      if (space > endOrig) {
        suffixEnd = space;
        hasTrailing = true;
      } else {
        hasTrailing = true;
      }
    }
    final suffixText = orig.substring(endOrig, suffixEnd);

    return SearchResult(
      verseId: ayah.verseId,
      surah: ayah.surah,
      ayah: ayah.ayah,
      uthmaniText: orig,
      excerptPrefix: prefixText,
      excerptMatch: matchText,
      excerptSuffix: suffixText,
      hasLeadingEllipsis: hasLeading,
      hasTrailingEllipsis: hasTrailing,
    );
  }
}

class _MappingResult {
  final String normalized;
  final List<int> origIndices;

  const _MappingResult(this.normalized, this.origIndices);
}
