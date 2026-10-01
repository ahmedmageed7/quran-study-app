import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';
import 'package:quran_app/database/user_data_models.dart';
import 'package:quran_app/quran_reader_screen.dart';
import 'package:quran_app/verse_category_menu.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  fail('Timed out waiting for category storage UI');
}

void main() {
  late Directory temp;
  late AppDatabase store;
  late Database db;
  late int firstId;
  late int secondId;
  const dao = UserDataDao();
  final firstMenu = find.byKey(const ValueKey('verse-categories-1-1'));
  Finder button() =>
      find.descendant(of: firstMenu, matching: find.byType(IconButton));
  Finder category(int id) => find.byKey(ValueKey('category-$id'));

  setUp(() async {
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('reader_categories_');
    store = AppDatabase.atPath(
      p.join(temp.path, 'user.db'),
      factory: databaseFactoryFfi,
    );
    db = await store.database;
    firstId = (await dao.getAllCategories(db)).first.id!;
    secondId = await dao.insertCategory(
      db,
      const Category(name: 'بند محفوظ', isBuiltin: false, sortOrder: 10),
    );
  });

  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('فتح القارئ'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QuranReaderScreen(database: store),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح القارئ'));
    await waitFor(tester, () => firstMenu.evaluate().isNotEmpty);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(button());
    await waitFor(tester, () => category(firstId).evaluate().isNotEmpty);
  }

  Future<void> toggle(WidgetTester tester, int id) async {
    await tester.ensureVisible(category(id));
    await tester.tap(category(id));
    await waitFor(
      tester,
      () => tester.widget<IconButton>(button()).onPressed != null,
    );
  }

  Future<void> addDialog(WidgetTester tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('إضافة بند'));
    await tester.tap(find.text('إضافة بند'));
    await waitFor(tester, () => find.byType(TextField).evaluate().isNotEmpty);
  }

  testWidgets(
    'custom category is trimmed, assigned, immediately listed and persisted',
    (tester) async {
      await launch(tester);
      await addDialog(tester);
      await tester.enterText(find.byType(TextField), '  بند جديد  ');
      await tester.tap(find.text('حفظ'));
      await waitFor(tester, () => find.text('بند جديد').evaluate().isNotEmpty);
      final created = (await tester.runAsync(() => dao.getAllCategories(db)))!
          .last;
      expect(created.name, 'بند جديد');
      expect(created.isBuiltin, isFalse);
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(created.id!)).checked,
        isTrue,
      );
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1),
        ),
        [created.id],
      );
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 2),
        ),
        isEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(() => store.close());
      db = (await tester.runAsync(() => store.database))!;
      await tester.tap(find.text('فتح القارئ'));
      await waitFor(tester, () => firstMenu.evaluate().isNotEmpty);
      await open(tester);
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(created.id!)).checked,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty and duplicate names show errors; cancellation writes nothing',
    (tester) async {
      await launch(tester);
      await addDialog(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      expect(find.text('أدخل اسم البند.'), findsOneWidget);
      for (final name in ['الفعل', 'بند محفوظ']) {
        await tester.enterText(find.byType(TextField), ' $name ');
        await tester.tap(find.text('حفظ'));
        await waitFor(
          tester,
          () => find
              .text('يوجد بند بهذا الاسم. اختر اسماً آخر.')
              .evaluate()
              .isNotEmpty,
        );
      }
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => dao.getAllCategories(db)))!.length,
        11,
      );
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed assignment rolls back category creation and allows retry',
    (tester) async {
      await launch(tester);
      await tester.runAsync(
        () => db.execute(
          "CREATE TRIGGER reject_custom BEFORE INSERT ON verse_categories BEGIN SELECT RAISE(ABORT, 'test failure'); END",
        ),
      );
      await addDialog(tester);
      await tester.enterText(find.byType(TextField), 'بند للتجربة');
      await tester.tap(find.text('حفظ'));
      await waitFor(
        tester,
        () =>
            find.text('تعذر إنشاء البند. حاول مرة أخرى.').evaluate().isNotEmpty,
      );
      expect(
        (await tester.runAsync(() => dao.getAllCategories(db)))!.length,
        11,
      );
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1),
        ),
        isEmpty,
      );
      await tester.runAsync(() => db.execute('DROP TRIGGER reject_custom'));
      await tester.tap(find.text('حفظ'));
      await waitFor(
        tester,
        () =>
            find.byType(TextField).evaluate().isEmpty &&
            find.text('بند للتجربة').evaluate().isNotEmpty,
      );
      final created = (await tester.runAsync(() => dao.getAllCategories(db)))!
          .last;
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(created.id!)).checked,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reader saves multiple categories, restores after exit, and removes one',
    (tester) async {
      await launch(tester);
      await open(tester);
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(firstId)).checked,
        isFalse,
      );
      await toggle(tester, firstId);
      await open(tester);
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(firstId)).checked,
        isTrue,
      );
      await toggle(tester, secondId);
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1),
        ),
        unorderedEquals([firstId, secondId]),
      );
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 2),
        ),
        isEmpty,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.runAsync(() => store.close());
      db = (await tester.runAsync(() => store.database))!;
      await tester.tap(find.text('فتح القارئ'));
      await waitFor(tester, () => firstMenu.evaluate().isNotEmpty);
      await open(tester);
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(firstId)).checked,
        isTrue,
      );
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(secondId)).checked,
        isTrue,
      );
      await toggle(tester, firstId);
      await open(tester);
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(firstId)).checked,
        isFalse,
      );
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(secondId)).checked,
        isTrue,
      );
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1),
        ),
        [secondId],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('every menu opening refreshes SQLite membership', (tester) async {
    await launch(tester);
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () =>
          dao.assignVerseToCategory(db, surah: 1, ayah: 1, categoryId: firstId),
    );
    await open(tester);
    expect(
      tester.widget<CheckedPopupMenuItem<int>>(category(firstId)).checked,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed write reports error without showing an unsaved selection',
    (tester) async {
      await launch(tester);
      await tester.runAsync(
        () => db.execute(
          "CREATE TRIGGER reject_assignment BEFORE INSERT ON verse_categories BEGIN SELECT RAISE(ABORT, 'test failure'); END",
        ),
      );
      await open(tester);
      await toggle(tester, firstId);
      expect(find.text('تعذر حفظ التصنيف. حاول مرة أخرى.'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1),
        ),
        isEmpty,
      );
      await open(tester);
      expect(
        tester.widget<CheckedPopupMenuItem<int>>(category(firstId)).checked,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed loading shows an error and permits retry', (
    tester,
  ) async {
    await tester.runAsync(
      () =>
          db.execute('ALTER TABLE categories RENAME TO unavailable_categories'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseCategoryMenu(surah: 1, ayah: 1, database: store),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await waitFor(
      tester,
      () => find
          .text('تعذر تحميل التصنيفات. حاول مرة أخرى.')
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(CheckedPopupMenuItem<int>), findsNothing);
    await tester.runAsync(
      () =>
          db.execute('ALTER TABLE unavailable_categories RENAME TO categories'),
    );
    await tester.tap(find.byType(IconButton));
    await waitFor(tester, () => category(firstId).evaluate().isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
