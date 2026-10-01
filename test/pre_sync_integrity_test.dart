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
  late Database db;
  late int customId;
  late int noteId;
  const dao = UserDataDao();
  const tables = [
    'categories',
    'verse_categories',
    'highlights',
    'notes',
    'reading_progress',
    'settings',
  ];
  final source = File('assets/quran/data/quran_data.json');
  late List<int> sourceBytes;

  Future<Map<String, List<Map<String, Object?>>>> snapshot(
    Database database,
  ) async => {
    for (final table in tables)
      table: await database.query(
        table,
        orderBy: table == 'settings' ? 'key' : 'id',
      ),
  };

  Future<void> checkIntegrity(Database database) async {
    expect(
      (await database.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  }

  setUp(() async {
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('pre_sync_audit_');
    store = AppDatabase.atPath(
      p.join(temp.path, 'user_data.db'),
      factory: databaseFactoryFfi,
    );
    db = await store.database;
    sourceBytes = await source.readAsBytes();
    customId = await dao.createCategoryForVerse(
      db,
      name: 'تدقيق',
      surah: 1,
      ayah: 1,
    );
    await dao.assignVerseToCategory(db, surah: 1, ayah: 1, categoryId: 1);
    for (final range in [(0, 'FFD54F'), (2, '64B5F6')]) {
      await dao.saveHighlight(
        db,
        Highlight(
          surah: 1,
          ayah: 1,
          tokenStart: range.$1,
          tokenEnd: range.$1,
          colorHex: range.$2,
          createdAtMs: 123,
        ),
        wordCount: 4,
      );
    }
    noteId = await dao.insertNote(
      db,
      const Note(
        surah: 1,
        ayah: 1,
        content: 'تأمل شخصيّ',
        createdAtMs: 123,
        updatedAtMs: 123,
      ),
    );
    await dao.saveReadingProgress(db, surah: 2, ayah: 255);
    await dao.setSetting(db, AppSettings.keyFontSize, '24');
    await dao.setSetting(db, AppSettings.keyThemeMode, 'dark');
  });
  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });

  for (final kind in ['category', 'highlight', 'note']) {
    test(
      '$kind edits and deletes preserve every unrelated user table after reopen',
      () async {
        final before = await snapshot(db);
        if (kind == 'category') {
          final category = (await dao.getAllCategories(db))
              .firstWhere((c) => c.id == customId);
          expect(
            await dao.updateCategory(
              db,
              category.copyWith(name: 'تدقيق معدّل'),
            ),
            1,
          );
          final edited = await snapshot(db);
          expect(edited['categories']!.last['name'], 'تدقيق معدّل');
          for (final table in tables.where((t) => t != 'categories')) {
            expect(
              edited[table],
              before[table],
              reason: 'Category edit changed $table',
            );
          }
          expect(await dao.deleteCategory(db, customId), 1);
        } else if (kind == 'highlight') {
          final highlight = (await dao.getHighlightsForVerse(
            db,
            surah: 1,
            ayah: 1,
          )).first;
          await dao.saveHighlight(
            db,
            Highlight(
              id: highlight.id,
              surah: 1,
              ayah: 1,
              tokenStart: 0,
              tokenEnd: 1,
              colorHex: '81C784',
              createdAtMs: highlight.createdAtMs,
            ),
            wordCount: 4,
          );
          final edited = await snapshot(db);
          expect(edited['highlights']!.first['token_end'], 1);
          expect(edited['highlights']!.first['color_hex'], '81C784');
          for (final table in tables.where((t) => t != 'highlights')) {
            expect(
              edited[table],
              before[table],
              reason: 'Highlight edit changed $table',
            );
          }
          expect(await dao.deleteHighlight(db, highlight.id!), 1);
        } else {
          expect(
            await dao.updateNote(db, noteId: noteId, content: 'تأمل معدّل'),
            1,
          );
          final edited = await snapshot(db);
          expect(edited['notes']!.single['content'], 'تأمل معدّل');
          for (final table in tables.where((t) => t != 'notes')) {
            expect(
              edited[table],
              before[table],
              reason: 'Note edit changed $table',
            );
          }
          expect(await dao.deleteNote(db, noteId), 1);
        }
        await store.close();
        db = await store.database;
        final after = await snapshot(db);
        final affected = switch (kind) {
          'category' => {'categories', 'verse_categories'},
          'highlight' => {'highlights'},
          _ => {'notes'},
        };
        for (final table in tables.where((t) => !affected.contains(t))) {
          expect(
            after[table],
            before[table],
            reason: '$kind deletion changed $table',
          );
        }
        if (kind == 'category') {
          expect(
            after['categories'],
            before['categories']!.where((r) => r['id'] != customId).toList(),
          );
          expect(
            after['verse_categories'],
            before['verse_categories']!
                .where((r) => r['category_id'] != customId)
                .toList(),
          );
        } else if (kind == 'highlight') {
          expect(after['highlights'], [before['highlights']!.last]);
        } else {
          expect(after['notes'], isEmpty);
        }
        await checkIntegrity(db);
        expect(await source.readAsBytes(), sourceBytes);
      },
    );
  }

  test('closed user-only database copy restores all six tables independently of Quran asset', () async {
    final before = await snapshot(db);
    await checkIntegrity(db);
    await store.close();
    final copyPath = p.join(temp.path, 'restored_user_data.db');
    await File(p.join(temp.path, 'user_data.db')).copy(copyPath);
    final restored = AppDatabase.atPath(copyPath, factory: databaseFactoryFfi);
    try {
      final restoredDb = await restored.database;
      expect(await snapshot(restoredDb), before);
      expect(await restoredDb.getVersion(), 1);
      await checkIntegrity(restoredDb);
      final actualTables = await restoredDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      );
      expect(actualTables.map((r) => r['name']), unorderedEquals(tables));
      await dao.deleteNote(restoredDb, noteId);
      expect(await snapshot(await store.database), before);
      expect(await source.readAsBytes(), sourceBytes);
    } finally {
      await restored.close();
    }
  });
}
