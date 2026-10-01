/// Stable token contract v1: zero-based non-whitespace runs, matching the
/// existing SQLite highlight IDs. Never normalize, trim, or rejoin the source.
class QuranToken {
  const QuranToken(this.id, this.start, this.end);
  final int id;
  // Transient source boundaries, used only for exact slices and text hit tests.
  // These are never persisted as user selections.
  final int start;
  final int end;
}

class QuranTokens {
  QuranTokens(this.source)
    : words = List.unmodifiable([
        for (final (i, match) in RegExp(r'\S+').allMatches(source).indexed)
          QuranToken(i, match.start, match.end),
      ]);

  final String source;
  final List<QuranToken> words;

  bool containsRange(int start, int end) =>
      start >= 0 && end >= start && end < words.length;

  String word(int id) => source.substring(words[id].start, words[id].end);

  String range(int start, int end) {
    if (!containsRange(start, end)) {
      throw RangeError('Highlight word IDs are outside the source ayah');
    }
    return source.substring(words[start].start, words[end].end);
  }
}
