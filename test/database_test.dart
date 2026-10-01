// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quran_app/database/user_data_models.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Uses the production schema; individual CRUD tests start with empty categories.
Future<Database> _openTestDb() async {
  final store = AppDatabase.atPath(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  final db = await store.database;
  await db.delete('categories');
  return db;
}
// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Database db;
  const dao = UserDataDao();

  setUpAll(() async {
    // Required for sqflite_common_ffi on desktop/CI.
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await _openTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  // =========================================================================
  // Category tests
  // =========================================================================

  group('Category CRUD', () {
    test('insert and retrieve category', () async {
      const cat = Category(name: 'الفعل', isBuiltin: true, sortOrder: 0);
      final id = await dao.insertCategory(db, cat);
      expect(id, greaterThan(0));

      final all = await dao.getAllCategories(db);
      expect(all.length, 1);
      expect(all.first.name, 'الفعل');
      expect(all.first.isBuiltin, isTrue);
      expect(all.first.id, id);
    });

    test('getAllCategories ordered by sort_order', () async {
      await dao.insertCategory(
        db,
        const Category(name: 'ب', isBuiltin: false, sortOrder: 2),
      );
      await dao.insertCategory(
        db,
        const Category(name: 'أ', isBuiltin: false, sortOrder: 1),
      );
      await dao.insertCategory(
        db,
        const Category(name: 'ج', isBuiltin: false, sortOrder: 3),
      );

      final all = await dao.getAllCategories(db);
      expect(all.map((c) => c.name).toList(), ['أ', 'ب', 'ج']);
    });

    test('update category name', () async {
      final id = await dao.insertCategory(
        db,
        const Category(name: 'قديم', isBuiltin: false, sortOrder: 0),
      );

      final updated = Category(
        id: id,
        name: 'جديد',
        isBuiltin: false,
        sortOrder: 0,
      );
      final rows = await dao.updateCategory(db, updated);
      expect(rows, 1);

      final all = await dao.getAllCategories(db);
      expect(all.first.name, 'جديد');
    });

    test('delete custom category', () async {
      final id = await dao.insertCategory(
        db,
        const Category(name: 'مؤقت', isBuiltin: false, sortOrder: 0),
      );

      final deleted = await dao.deleteCategory(db, id);
      expect(deleted, 1);

      final all = await dao.getAllCategories(db);
      expect(all, isEmpty);
    });

    test('cannot delete builtin category', () async {
      final id = await dao.insertCategory(
        db,
        const Category(name: 'ثابت', isBuiltin: true, sortOrder: 0),
      );

      final deleted = await dao.deleteCategory(db, id);
      expect(deleted, 0, reason: 'Built-in categories must not be deletable');

      final all = await dao.getAllCategories(db);
      expect(all.length, 1);
    });

    test('duplicate category name raises exception', () async {
      await dao.insertCategory(
        db,
        const Category(name: 'مكرر', isBuiltin: false, sortOrder: 0),
      );

      expect(
        () => dao.insertCategory(
          db,
          const Category(name: 'مكرر', isBuiltin: false, sortOrder: 1),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  // =========================================================================
  // VerseCategory tests
  // =========================================================================

  group('VerseCategory CRUD', () {
    late int catId;

    setUp(() async {
      catId = await dao.insertCategory(
        db,
        const Category(name: 'الأوامر', isBuiltin: true, sortOrder: 0),
      );
    });

    test('assign verse to category and retrieve', () async {
      await dao.assignVerseToCategory(db, surah: 2, ayah: 1, categoryId: catId);

      final ids = await dao.getCategoryIdsForVerse(db, surah: 2, ayah: 1);
      expect(ids, [catId]);
    });

    test('assign verse returns silently on duplicate', () async {
      await dao.assignVerseToCategory(db, surah: 2, ayah: 1, categoryId: catId);
      // second call must not throw
      await dao.assignVerseToCategory(db, surah: 2, ayah: 1, categoryId: catId);

      final ids = await dao.getCategoryIdsForVerse(db, surah: 2, ayah: 1);
      expect(ids.length, 1);
    });

    test('getVersesForCategory returns correct rows ordered', () async {
      await dao.assignVerseToCategory(db, surah: 3, ayah: 5, categoryId: catId);
      await dao.assignVerseToCategory(
        db,
        surah: 2,
        ayah: 10,
        categoryId: catId,
      );
      await dao.assignVerseToCategory(db, surah: 2, ayah: 3, categoryId: catId);

      final verses = await dao.getVersesForCategory(db, categoryId: catId);
      expect(verses.length, 3);
      expect(verses[0].surah, 2);
      expect(verses[0].ayah, 3);
      expect(verses[1].surah, 2);
      expect(verses[1].ayah, 10);
      expect(verses[2].surah, 3);
      expect(verses[2].ayah, 5);
    });

    test('remove verse from category', () async {
      await dao.assignVerseToCategory(db, surah: 1, ayah: 1, categoryId: catId);
      final removed = await dao.removeVerseFromCategory(
        db,
        surah: 1,
        ayah: 1,
        categoryId: catId,
      );
      expect(removed, 1);

      final ids = await dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1);
      expect(ids, isEmpty);
    });

    test('toggleVerseCategory assigns then removes', () async {
      final assigned = await dao.toggleVerseCategory(
        db,
        surah: 4,
        ayah: 7,
        categoryId: catId,
      );
      expect(assigned, isTrue);

      final removed = await dao.toggleVerseCategory(
        db,
        surah: 4,
        ayah: 7,
        categoryId: catId,
      );
      expect(removed, isFalse);

      final ids = await dao.getCategoryIdsForVerse(db, surah: 4, ayah: 7);
      expect(ids, isEmpty);
    });

    test('deleting category cascades to verse_categories', () async {
      final customId = await dao.insertCategory(
        db,
        const Category(name: 'مخصص', isBuiltin: false, sortOrder: 1),
      );
      await dao.assignVerseToCategory(
        db,
        surah: 5,
        ayah: 2,
        categoryId: customId,
      );

      await dao.deleteCategory(db, customId);

      final ids = await dao.getCategoryIdsForVerse(db, surah: 5, ayah: 2);
      expect(
        ids,
        isEmpty,
        reason: 'Cascade delete should remove verse_categories',
      );
    });

    test('verse can belong to multiple categories', () async {
      final catId2 = await dao.insertCategory(
        db,
        const Category(name: 'النواهي', isBuiltin: true, sortOrder: 1),
      );

      await dao.assignVerseToCategory(db, surah: 1, ayah: 1, categoryId: catId);
      await dao.assignVerseToCategory(
        db,
        surah: 1,
        ayah: 1,
        categoryId: catId2,
      );

      final ids = await dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1);
      expect(ids.toSet(), {catId, catId2});
    });
  });

  // =========================================================================
  // Highlight tests
  // =========================================================================

  group('Highlight CRUD', () {
    test('insert and retrieve highlight by verse', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final h = Highlight(
        surah: 2,
        ayah: 255,
        tokenStart: 0,
        tokenEnd: 2,
        colorHex: 'FFD700',
        createdAtMs: nowMs,
      );
      final id = await dao.insertHighlight(db, h);
      expect(id, greaterThan(0));

      final list = await dao.getHighlightsForVerse(db, surah: 2, ayah: 255);
      expect(list.length, 1);
      expect(list.first.tokenStart, 0);
      expect(list.first.tokenEnd, 2);
      expect(list.first.colorHex, 'FFD700');
    });

    test('multiple highlights on same verse ordered by tokenStart', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      await dao.insertHighlight(
        db,
        Highlight(
          surah: 1,
          ayah: 1,
          tokenStart: 3,
          tokenEnd: 4,
          colorHex: 'FF0000',
          createdAtMs: nowMs,
        ),
      );
      await dao.insertHighlight(
        db,
        Highlight(
          surah: 1,
          ayah: 1,
          tokenStart: 0,
          tokenEnd: 1,
          colorHex: '00FF00',
          createdAtMs: nowMs,
        ),
      );

      final list = await dao.getHighlightsForVerse(db, surah: 1, ayah: 1);
      expect(list.length, 2);
      expect(list[0].tokenStart, 0);
      expect(list[1].tokenStart, 3);
    });

    test('delete highlight by id', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final id = await dao.insertHighlight(
        db,
        Highlight(
          surah: 3,
          ayah: 10,
          tokenStart: 1,
          tokenEnd: 1,
          colorHex: 'AABBCC',
          createdAtMs: nowMs,
        ),
      );

      final deleted = await dao.deleteHighlight(db, id);
      expect(deleted, 1);

      final list = await dao.getHighlightsForVerse(db, surah: 3, ayah: 10);
      expect(list, isEmpty);
    });

    test('getHighlightsForVerse returns empty for untagged verse', () async {
      final list = await dao.getHighlightsForVerse(db, surah: 99, ayah: 99);
      expect(list, isEmpty);
    });
  });

  // =========================================================================
  // ReadingProgress tests
  // =========================================================================

  group('ReadingProgress', () {
    test('returns null when no progress saved', () async {
      final progress = await dao.getReadingProgress(db);
      expect(progress, isNull);
    });

    test('save and retrieve reading position', () async {
      await dao.saveReadingProgress(db, surah: 2, ayah: 255);
      final p = await dao.getReadingProgress(db);
      expect(p, isNotNull);
      expect(p!.surah, 2);
      expect(p.ayah, 255);
    });

    test('upsert overwrites previous position', () async {
      await dao.saveReadingProgress(db, surah: 1, ayah: 1);
      await dao.saveReadingProgress(db, surah: 36, ayah: 83);

      final p = await dao.getReadingProgress(db);
      expect(p!.surah, 36);
      expect(p.ayah, 83);
    });
  });

  // =========================================================================
  // Settings tests
  // =========================================================================

  group('Settings', () {
    test('returns defaultValue when key not set', () async {
      final val = await dao.getSetting(
        db,
        'missing_key',
        defaultValue: 'fallback',
      );
      expect(val, 'fallback');
    });

    test('set and get setting', () async {
      await dao.setSetting(db, AppSettings.keyFontSize, '22.0');
      final val = await dao.getSetting(db, AppSettings.keyFontSize);
      expect(val, '22.0');
    });

    test('setSetting overwrites existing value', () async {
      await dao.setSetting(db, AppSettings.keyThemeMode, 'light');
      await dao.setSetting(db, AppSettings.keyThemeMode, 'dark');
      final val = await dao.getSetting(db, AppSettings.keyThemeMode);
      expect(val, 'dark');
    });

    test('deleteSetting removes key', () async {
      await dao.setSetting(db, 'temp', 'value');
      await dao.deleteSetting(db, 'temp');
      final val = await dao.getSetting(db, 'temp');
      expect(val, isNull);
    });
  });

  // =========================================================================
  // Notes tests
  // =========================================================================

  group('Notes CRUD', () {
    test('insert and retrieve general note', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final note = Note(
        content: 'ملاحظة عامة',
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );
      final id = await dao.insertNote(db, note);
      expect(id, greaterThan(0));

      final all = await dao.getAllNotes(db);
      expect(all.length, 1);
      expect(all.first.content, 'ملاحظة عامة');
      expect(all.first.surah, isNull);
      expect(all.first.ayah, isNull);
    });

    test('insert and retrieve verse-linked note', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final note = Note(
        surah: 2,
        ayah: 1,
        content: 'ملاحظة الآية',
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );
      await dao.insertNote(db, note);

      final verseNotes = await dao.getNotesForVerse(db, surah: 2, ayah: 1);
      expect(verseNotes.length, 1);
      expect(verseNotes.first.content, 'ملاحظة الآية');
    });

    test('update note content', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final id = await dao.insertNote(
        db,
        Note(content: 'قديم', createdAtMs: nowMs, updatedAtMs: nowMs),
      );

      final rows = await dao.updateNote(db, noteId: id, content: 'جديد');
      expect(rows, 1);

      final all = await dao.getAllNotes(db);
      expect(all.first.content, 'جديد');
    });

    test('delete note', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final id = await dao.insertNote(
        db,
        Note(content: 'للحذف', createdAtMs: nowMs, updatedAtMs: nowMs),
      );

      final deleted = await dao.deleteNote(db, id);
      expect(deleted, 1);

      final all = await dao.getAllNotes(db);
      expect(all, isEmpty);
    });

    test('getAllNotes ordered by updatedAtMs DESC', () async {
      final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
      final t2 = t1 + 1000;
      await dao.insertNote(
        db,
        Note(content: 'أولى', createdAtMs: t1, updatedAtMs: t1),
      );
      await dao.insertNote(
        db,
        Note(content: 'ثانية', createdAtMs: t2, updatedAtMs: t2),
      );

      final all = await dao.getAllNotes(db);
      expect(all[0].content, 'ثانية');
      expect(all[1].content, 'أولى');
    });

    test('getNotesForVerse returns empty for verse with no notes', () async {
      final notes = await dao.getNotesForVerse(db, surah: 99, ayah: 99);
      expect(notes, isEmpty);
    });
  });

  // =========================================================================
  // Data integrity: Quran data never modified
  // =========================================================================

  group('Data separation integrity', () {
    test('no Quran text column exists in any table', () async {
      // Fetch PRAGMA table_info for all user tables and verify no column
      // is named 'text' or 'uthmani' — those belong to the immutable Quran
      // layer only.
      const tables = [
        'categories',
        'verse_categories',
        'highlights',
        'reading_progress',
        'settings',
        'notes',
      ];
      final bannedColumns = {'text', 'uthmani', 'quran_text', 'arabic_text'};

      for (final table in tables) {
        final info = await db.rawQuery('PRAGMA table_info($table)');
        final columnNames = info
            .map((r) => (r['name'] as String).toLowerCase())
            .toSet();
        final overlap = columnNames.intersection(bannedColumns);
        expect(
          overlap,
          isEmpty,
          reason:
              'Table "$table" must not store Quran text. '
              'Found banned columns: $overlap',
        );
      }
    });
  });
}
