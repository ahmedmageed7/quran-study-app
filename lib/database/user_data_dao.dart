/// UserDataDao — Data Access Object for all user data tables.
///
/// All methods take the open [Database] as a parameter so that:
/// - Production code passes `await AppDatabase.instance.database`.
/// - Tests can pass an in-memory sqflite database without touching the
///   singleton.
///
/// No Quran text is ever stored or returned by this DAO.
library;

import 'package:sqflite/sqflite.dart';

import 'user_data_models.dart';

class HighlightOverlapException implements Exception {}

class UserDataDao {
  const UserDataDao();

  // =========================================================================
  // Categories
  // =========================================================================

  /// Returns all categories ordered by [sortOrder].
  Future<List<Category>> getAllCategories(Database db) async {
    final rows = await db.query(
      'categories',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  /// Inserts a new category and returns its assigned id.
  Future<int> insertCategory(DatabaseExecutor db, Category category) async {
    return db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Creates and assigns together so a failed assignment leaves no orphan.
  /// Duplicate names are rejected by the existing SQLite UNIQUE constraint.
  Future<int> createCategoryForVerse(
    Database db, {
    required String name,
    required int surah,
    required int ayah,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Empty category');
    }
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT MAX(sort_order) AS last_order FROM categories',
      );
      final id = await insertCategory(
        txn,
        Category(
          name: trimmed,
          isBuiltin: false,
          sortOrder: ((rows.single['last_order'] as int?) ?? -1) + 1,
        ),
      );
      await assignVerseToCategory(
        txn,
        surah: surah,
        ayah: ayah,
        categoryId: id,
      );
      return id;
    });
  }

  /// Updates an existing category. Returns number of rows changed (0 or 1).
  Future<int> updateCategory(Database db, Category category) async {
    assert(category.id != null, 'Cannot update a category without an id');
    return db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  /// Deletes a custom (non-builtin) category and cascades to verse_categories.
  /// Returns number of rows deleted.
  Future<int> deleteCategory(Database db, int categoryId) async {
    return db.delete(
      'categories',
      where: 'id = ? AND is_builtin = 0',
      whereArgs: [categoryId],
    );
  }

  // =========================================================================
  // VerseCategories
  // =========================================================================

  /// Returns all category IDs assigned to the given (surah, ayah).
  Future<List<int>> getCategoryIdsForVerse(
    Database db, {
    required int surah,
    required int ayah,
  }) async {
    final rows = await db.query(
      'verse_categories',
      columns: ['category_id'],
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
    );
    return rows.map((r) => r['category_id'] as int).toList();
  }

  /// Returns all [VerseCategory] rows for the given [categoryId], ordered by
  /// surah then ayah.
  Future<List<VerseCategory>> getVersesForCategory(
    Database db, {
    required int categoryId,
  }) async {
    final rows = await db.query(
      'verse_categories',
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'surah ASC, ayah ASC',
    );
    return rows.map(VerseCategory.fromMap).toList();
  }

  /// Assigns an ayah to a category.  Silently ignores duplicate assignment.
  /// Returns SQLite's insert result; callers must not use it to identify a
  /// pre-existing relationship when the insert was ignored.
  Future<int> assignVerseToCategory(
    DatabaseExecutor db, {
    required int surah,
    required int ayah,
    required int categoryId,
  }) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.insert(
      'verse_categories',
      VerseCategory(
        surah: surah,
        ayah: ayah,
        categoryId: categoryId,
        createdAtMs: nowMs,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Removes an ayah from a category. Returns number of rows deleted (0 or 1).
  Future<int> removeVerseFromCategory(
    Database db, {
    required int surah,
    required int ayah,
    required int categoryId,
  }) async {
    return db.delete(
      'verse_categories',
      where: 'surah = ? AND ayah = ? AND category_id = ?',
      whereArgs: [surah, ayah, categoryId],
    );
  }

  /// Toggles category membership.  Assigns if not present; removes if present.
  /// Returns `true` if the verse is now assigned, `false` if removed.
  Future<bool> toggleVerseCategory(
    Database db, {
    required int surah,
    required int ayah,
    required int categoryId,
  }) async {
    return db.transaction((txn) async {
      final existing = await txn.query(
        'verse_categories',
        where: 'surah = ? AND ayah = ? AND category_id = ?',
        whereArgs: [surah, ayah, categoryId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(
          'verse_categories',
          VerseCategory(
            surah: surah,
            ayah: ayah,
            categoryId: categoryId,
            createdAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ).toMap(),
        );
        return true;
      } else {
        await txn.delete(
          'verse_categories',
          where: 'surah = ? AND ayah = ? AND category_id = ?',
          whereArgs: [surah, ayah, categoryId],
        );
        return false;
      }
    });
  }

  // =========================================================================
  // Highlights
  // =========================================================================

  /// Returns all highlights for the given (surah, ayah).
  Future<List<Highlight>> getHighlightsForVerse(
    Database db, {
    required int surah,
    required int ayah,
  }) async {
    final rows = await db.query(
      'highlights',
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
      orderBy: 'token_start ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  /// Inserts a new highlight and returns its row id.
  Future<int> insertHighlight(Database db, Highlight highlight) async {
    return db.insert(
      'highlights',
      highlight.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Atomically creates/edits one range without hiding other highlights.
  /// Text is never accepted or stored; wordCount comes from the source tokens.
  Future<void> saveHighlight(
    Database db,
    Highlight highlight, {
    required int wordCount,
  }) async {
    if (highlight.tokenStart < 0 ||
        highlight.tokenEnd < highlight.tokenStart ||
        highlight.tokenEnd >= wordCount ||
        !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(highlight.colorHex)) {
      throw ArgumentError('Invalid highlight range or color');
    }
    await db.transaction((txn) async {
      final overlaps = await txn.query(
        'highlights',
        columns: ['id'],
        where: 'surah = ? AND ayah = ? AND token_start <= ? AND token_end >= ? AND id != ?',
        whereArgs: [
          highlight.surah,
          highlight.ayah,
          highlight.tokenEnd,
          highlight.tokenStart,
          highlight.id ?? -1,
        ],
      );
      if (overlaps.isNotEmpty) throw HighlightOverlapException();
      if (highlight.id == null) {
        await txn.insert('highlights', highlight.toMap());
      } else {
        final count = await txn.update(
          'highlights',
          highlight.toMap(),
          where: 'id = ? AND surah = ? AND ayah = ?',
          whereArgs: [highlight.id, highlight.surah, highlight.ayah],
        );
        if (count != 1) throw StateError('Highlight no longer exists');
      }
    });
  }

  /// Deletes a highlight by id. Returns number of rows deleted (0 or 1).
  Future<int> deleteHighlight(Database db, int highlightId) async {
    return db.delete('highlights', where: 'id = ?', whereArgs: [highlightId]);
  }

  // =========================================================================
  // ReadingProgress
  // =========================================================================

  /// Returns the last reading position, or `null` if never saved.
  Future<ReadingProgress?> getReadingProgress(Database db) async {
    final rows = await db.query(
      'reading_progress',
      where: 'id = ?',
      whereArgs: [ReadingProgress.singletonId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReadingProgress.fromMap(rows.first);
  }

  /// Upserts the reading position (insert or replace).
  Future<void> saveReadingProgress(
    Database db, {
    required int surah,
    required int ayah,
  }) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert(
      'reading_progress',
      ReadingProgress(surah: surah, ayah: ayah, updatedAtMs: nowMs).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // =========================================================================
  // Settings
  // =========================================================================

  /// Returns the value for [key], or [defaultValue] if not set.
  Future<String?> getSetting(
    Database db,
    String key, {
    String? defaultValue,
  }) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return defaultValue;
    return rows.first['value'] as String;
  }

  /// Upserts a setting key-value pair.
  Future<void> setSetting(Database db, String key, String value) async {
    await db.insert(
      'settings',
      AppSettings(key: key, value: value).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a setting by key. Returns number of rows deleted (0 or 1).
  Future<int> deleteSetting(Database db, String key) async {
    return db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  // =========================================================================
  // Notes
  // =========================================================================

  /// Returns all notes, ordered by most recently updated.
  Future<List<Note>> getAllNotes(Database db) async {
    final rows = await db.query(
      'notes',
      orderBy: 'updated_at_ms DESC, id DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  /// Returns notes linked to a specific (surah, ayah).
  Future<List<Note>> getNotesForVerse(
    Database db, {
    required int surah,
    required int ayah,
  }) async {
    final rows = await db.query(
      'notes',
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
      orderBy: 'updated_at_ms DESC, id DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  /// Inserts a new note and returns its row id.
  Future<int> insertNote(Database db, Note note) async {
    _validateNoteContent(note.content);
    if ((note.surah == null) != (note.ayah == null) ||
        (note.surah != null &&
            (note.surah! < 1 || note.surah! > 114 || note.ayah! < 1))) {
      throw ArgumentError('Invalid note reference');
    }
    return db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Updates an existing note's content and [updatedAtMs]. Returns rows changed.
  Future<int> updateNote(
    Database db, {
    required int noteId,
    required String content,
  }) async {
    _validateNoteContent(content);
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.update(
      'notes',
      {'content': content, 'updated_at_ms': nowMs},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  /// Deletes a note by id. Returns number of rows deleted (0 or 1).
  Future<int> deleteNote(Database db, int noteId) async {
    return db.delete('notes', where: 'id = ?', whereArgs: [noteId]);
  }

  void _validateNoteContent(String content) {
    if (content.trim().isEmpty) throw ArgumentError('Empty note');
  }
}
