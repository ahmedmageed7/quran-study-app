/// User data models — strictly separated from immutable Quran data.
///
/// None of these models store or modify Quran text.
/// References to Quran data use (surah, ayah) integer pairs only.
library;

import '../quran_tokens.dart';

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

/// A user-defined category (e.g. "الفعل", "الأوامر").
///
/// Built-in categories have [isBuiltin] = true and are seeded at first run.
/// Custom categories added by the user have [isBuiltin] = false.
class Category {
  final int? id;
  final String name;
  final bool isBuiltin;

  /// Ordering weight for display; lower = first.
  final int sortOrder;

  const Category({
    this.id,
    required this.name,
    required this.isBuiltin,
    required this.sortOrder,
  });

  Category copyWith({int? id, String? name, bool? isBuiltin, int? sortOrder}) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'is_builtin': isBuiltin ? 1 : 0,
    'sort_order': sortOrder,
  };

  factory Category.fromMap(Map<String, dynamic> map) => Category(
    id: map['id'] as int?,
    name: map['name'] as String,
    isBuiltin: (map['is_builtin'] as int) == 1,
    sortOrder: map['sort_order'] as int,
  );

  @override
  String toString() => 'Category(id=$id, name=$name, builtin=$isBuiltin)';
}

// ---------------------------------------------------------------------------
// VerseCategory  (ayah ↔ category relationship)
// ---------------------------------------------------------------------------

/// Relationship between an ayah and a [Category].
///
/// An ayah is identified by [surah] + [ayah] integers referencing the
/// immutable Quran dataset. No Quran text is stored here.
class VerseCategory {
  final int? id;
  final int surah;
  final int ayah;
  final int categoryId;

  /// When the user assigned this category, stored as UTC milliseconds.
  final int createdAtMs;

  const VerseCategory({
    this.id,
    required this.surah,
    required this.ayah,
    required this.categoryId,
    required this.createdAtMs,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'surah': surah,
    'ayah': ayah,
    'category_id': categoryId,
    'created_at_ms': createdAtMs,
  };

  factory VerseCategory.fromMap(Map<String, dynamic> map) => VerseCategory(
    id: map['id'] as int?,
    surah: map['surah'] as int,
    ayah: map['ayah'] as int,
    categoryId: map['category_id'] as int,
    createdAtMs: map['created_at_ms'] as int,
  );

  @override
  String toString() =>
      'VerseCategory(surah=$surah, ayah=$ayah, cat=$categoryId)';
}

// ---------------------------------------------------------------------------
// Highlight
// ---------------------------------------------------------------------------

/// A user highlight on a portion of an ayah.
///
/// ## Unicode / Grapheme safety
/// Arabic Uthmani text contains multi-code-unit grapheme clusters (base letter
/// + harakat + Quranic symbols). Simple `String` character offsets are
/// UNRELIABLE because splitting on code-unit boundaries can break combining
/// marks.
///
/// Instead, we store **word token IDs**: the word index within the
/// ayah ([tokenStart] inclusive) and ([tokenEnd] inclusive), where each token
/// is a whitespace-delimited word of the original Uthmani text.
///
/// This is safe because:
/// - Arabic words are delimited by U+0020 space in the Uthmani dataset.
/// - We never store or modify the actual text.
/// - Reconstruction at render time iterates over the immutable original text
///   by word index only.
///
/// [colorHex] is a 6-digit hex string without '#', e.g. `"FFD700"`.
class Highlight {
  final int? id;
  final int surah;
  final int ayah;

  /// Zero-based index of the first highlighted word (token) in the ayah.
  final int tokenStart;

  /// Zero-based index of the last highlighted word (token) in the ayah (inclusive).
  final int tokenEnd;

  /// Highlight color as 6-digit uppercase hex, e.g. `"FFD700"`.
  final String colorHex;

  /// UTC milliseconds when the highlight was created.
  final int createdAtMs;

  const Highlight({
    this.id,
    required this.surah,
    required this.ayah,
    required this.tokenStart,
    required this.tokenEnd,
    required this.colorHex,
    required this.createdAtMs,
  });

  /// Resolves inclusive word IDs against the unchanged source text.
  /// Tokens are non-whitespace runs, including any attached Quranic marks.
  /// Original spacing and combining marks inside the selection are preserved.
  /// The caller supplies source text; it is never persisted in this model.
  String selectedText(String originalText) {
    return QuranTokens(originalText).range(tokenStart, tokenEnd);
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'surah': surah,
    'ayah': ayah,
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'color_hex': colorHex,
    'created_at_ms': createdAtMs,
  };

  factory Highlight.fromMap(Map<String, dynamic> map) => Highlight(
    id: map['id'] as int?,
    surah: map['surah'] as int,
    ayah: map['ayah'] as int,
    tokenStart: map['token_start'] as int,
    tokenEnd: map['token_end'] as int,
    colorHex: map['color_hex'] as String,
    createdAtMs: map['created_at_ms'] as int,
  );

  @override
  String toString() =>
      'Highlight(surah=$surah, ayah=$ayah, tokens=$tokenStart-$tokenEnd, '
      'color=#$colorHex)';
}

// ---------------------------------------------------------------------------
// ReadingProgress
// ---------------------------------------------------------------------------

/// Stores the last reading position so the reader can resume automatically.
///
/// Only one row is kept (id = 1). The reader upserts this on scroll/pause.
class ReadingProgress {
  static const int singletonId = 1;

  final int surah;
  final int ayah;

  /// UTC milliseconds when this position was last saved.
  final int updatedAtMs;

  const ReadingProgress({
    required this.surah,
    required this.ayah,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toMap() => {
    'id': singletonId,
    'surah': surah,
    'ayah': ayah,
    'updated_at_ms': updatedAtMs,
  };

  factory ReadingProgress.fromMap(Map<String, dynamic> map) => ReadingProgress(
    surah: map['surah'] as int,
    ayah: map['ayah'] as int,
    updatedAtMs: map['updated_at_ms'] as int,
  );

  @override
  String toString() => 'ReadingProgress(surah=$surah, ayah=$ayah)';
}

// ---------------------------------------------------------------------------
// AppSettings
// ---------------------------------------------------------------------------

/// Key-value settings store.
///
/// All values are persisted as strings; numeric/boolean helpers are provided.
/// Only one row per key is kept (key is the primary key).
class AppSettings {
  final String key;
  final String value;

  const AppSettings({required this.key, required this.value});

  Map<String, dynamic> toMap() => {'key': key, 'value': value};

  factory AppSettings.fromMap(Map<String, dynamic> map) =>
      AppSettings(key: map['key'] as String, value: map['value'] as String);

  // ---------------------------------------------------------------------------
  // Well-known setting keys
  // ---------------------------------------------------------------------------

  /// Font size for Quran reader (double stored as string).
  static const String keyFontSize = 'font_size';

  /// Theme mode: "dark" | "light" | "system".
  static const String keyThemeMode = 'theme_mode';

  @override
  String toString() => 'AppSettings($key=$value)';
}

// ---------------------------------------------------------------------------
// Note
// ---------------------------------------------------------------------------

/// A free-text note optionally linked to a specific ayah.
///
/// [surah] and [ayah] are nullable; if null the note is a general note
/// not tied to any verse.
class Note {
  final int? id;
  final int? surah;
  final int? ayah;
  final String content;
  final int createdAtMs;
  final int updatedAtMs;

  const Note({
    this.id,
    this.surah,
    this.ayah,
    required this.content,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'surah': surah,
    'ayah': ayah,
    'content': content,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };

  factory Note.fromMap(Map<String, dynamic> map) => Note(
    id: map['id'] as int?,
    surah: map['surah'] as int?,
    ayah: map['ayah'] as int?,
    content: map['content'] as String,
    createdAtMs: map['created_at_ms'] as int,
    updatedAtMs: map['updated_at_ms'] as int,
  );

  @override
  String toString() => 'Note(id=$id, surah=$surah, ayah=$ayah)';
}
