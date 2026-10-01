import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';
import 'package:quran_app/database/user_data_models.dart';

void main() {
  late Directory temp;
  late AppDatabase store;
  const dao = UserDataDao();

  setUp(() async {
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('quran_user_storage_');
    store = AppDatabase.atPath(
      p.join(temp.path, 'user_data.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });

  test('production database creates tables, indexes and seeds once', () async {
    final connections = await Future.wait([store.database, store.database]);
    expect(identical(connections[0], connections[1]), isTrue);
    final db = connections.first;
    expect(await File(p.join(temp.path, 'user_data.db')).exists(), isTrue);
    expect(await db.getVersion(), 1);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    expect(
      tables.map((r) => r['name']),
      unorderedEquals([
        'categories',
        'verse_categories',
        'highlights',
        'reading_progress',
        'settings',
        'notes',
      ]),
    );
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    expect(
      indexes.map((r) => r['name']),
      containsAll([
        'idx_vc_category',
        'idx_vc_verse',
        'idx_hl_verse',
        'idx_notes_verse',
      ]),
    );
    expect((await db.rawQuery('PRAGMA foreign_keys')).single.values.single, 1);
    final categories = await dao.getAllCategories(db);
    expect(categories.length, 10);
    expect(categories.every((c) => c.isBuiltin), isTrue);
    await store.close();
    expect(
      (await dao.getAllCategories(await store.database)).map((c) => c.toMap()),
      categories.map((c) => c.toMap()),
    );
  });

  test(
    'user records and Unicode word selections survive closing and reopening',
    () async {
      var db = await store.database;
      final category = await dao.insertCategory(
        db,
        const Category(name: 'بند شخصي', isBuiltin: false, sortOrder: 10),
      );
      final builtin = (await dao.getAllCategories(db)).first.id!;
      for (final id in [category, builtin]) {
        await dao.assignVerseToCategory(db, surah: 1, ayah: 1, categoryId: id);
      }
      await dao.saveReadingProgress(db, surah: 2, ayah: 255);
      await dao.setSetting(db, AppSettings.keyFontSize, '24');
      await dao.insertHighlight(
        db,
        const Highlight(
          surah: 1,
          ayah: 1,
          tokenStart: 1,
          tokenEnd: 2,
          colorHex: 'FFD700',
          createdAtMs: 123,
        ),
      );
      await dao.insertNote(
        db,
        const Note(content: 'ملاحظة', createdAtMs: 1, updatedAtMs: 1),
      );
      await store.close();
      // A new wrapper exercises persistence independently of cached state.
      store = AppDatabase.atPath(
        p.join(temp.path, 'user_data.db'),
        factory: databaseFactoryFfi,
      );
      db = await store.database;
      expect(
        await dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1),
        unorderedEquals([category, builtin]),
      );
      final progress = await dao.getReadingProgress(db);
      expect([progress!.surah, progress.ayah], [2, 255]);
      expect(await dao.getSetting(db, AppSettings.keyFontSize), '24');
      expect((await dao.getAllNotes(db)).single.content, 'ملاحظة');
      final highlight = (await dao.getHighlightsForVerse(
        db,
        surah: 1,
        ayah: 1,
      )).single;
      expect(highlight.colorHex, 'FFD700');
      const original = 'بِسْمِ ٱللَّهِ  ٱلرَّحْمَـٰنِ ٱلرَّحِيمِۖ';
      expect(highlight.selectedText(original), 'ٱللَّهِ  ٱلرَّحْمَـٰنِ');
      const endWord = Highlight(
        surah: 1,
        ayah: 1,
        tokenStart: 3,
        tokenEnd: 3,
        colorHex: '00FF00',
        createdAtMs: 1,
      );
      expect(endWord.selectedText(original), 'ٱلرَّحِيمِۖ');
      expect(() => highlight.selectedText('كلمة'), throwsRangeError);
    },
  );

  test(
    'concurrent toggles serialize and invalid word ranges are rejected',
    () async {
      final db = await store.database;
      final category = (await dao.getAllCategories(db)).first.id!;
      final toggles = await Future.wait([
        dao.toggleVerseCategory(db, surah: 1, ayah: 1, categoryId: category),
        dao.toggleVerseCategory(db, surah: 1, ayah: 1, categoryId: category),
      ]);
      expect(toggles, [true, false]);
      expect(await dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1), isEmpty);
      for (final range in [
        [-1, 0],
        [2, 1],
      ]) {
        await expectLater(
          dao.insertHighlight(
            db,
            Highlight(
              surah: 1,
              ayah: 1,
              tokenStart: range[0],
              tokenEnd: range[1],
              colorHex: 'FFD700',
              createdAtMs: 1,
            ),
          ),
          throwsA(isA<DatabaseException>()),
        );
      }
    },
  );

  test(
    'deleting all user records leaves Quran asset bytes unchanged',
    () async {
      final asset = File('assets/quran/data/quran_data.json');
      final before = await asset.readAsBytes();
      final db = await store.database;
      final category = await dao.insertCategory(
        db,
        const Category(name: 'للحذف', isBuiltin: false, sortOrder: 10),
      );
      await dao.assignVerseToCategory(
        db,
        surah: 1,
        ayah: 1,
        categoryId: category,
      );
      await dao.insertHighlight(
        db,
        const Highlight(
          surah: 1,
          ayah: 1,
          tokenStart: 0,
          tokenEnd: 0,
          colorHex: 'FFD700',
          createdAtMs: 1,
        ),
      );
      await dao.saveReadingProgress(db, surah: 1, ayah: 1);
      await dao.setSetting(db, 'theme_mode', 'dark');
      await dao.insertNote(
        db,
        const Note(content: 'مؤقت', createdAtMs: 1, updatedAtMs: 1),
      );
      await db.transaction((txn) async {
        for (final table in [
          'verse_categories',
          'categories',
          'highlights',
          'reading_progress',
          'settings',
          'notes',
        ]) {
          await txn.delete(table);
          expect(await txn.query(table), isEmpty);
        }
      });
      await store.close();
      expect(await asset.readAsBytes(), orderedEquals(before));
    },
  );
}
