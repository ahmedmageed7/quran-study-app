import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quran_app/category_screen.dart';
import 'package:quran_app/home_screen.dart';
import 'package:quran_app/quran_reader_screen.dart';
import 'package:quran_app/quran_repository.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';
import 'package:quran_app/database/user_data_models.dart';

Future<void> waitReady(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Timed out waiting for category page');
}

void main() {
  late Directory temp;
  late AppDatabase store;
  late Database db;
  late Category category;
  late List<QuranAyah> ayahs;
  const dao = UserDataDao();

  setUp(() async {
    // Do not reuse asset futures owned by a previous test's FakeAsync zone.
    rootBundle.evict('assets/quran/data/quran_data.json');
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('category_page_');
    store = AppDatabase.atPath(
      p.join(temp.path, 'user.db'),
      factory: databaseFactoryFfi,
    );
    db = await store.database;
    final id = await dao.insertCategory(
      db,
      const Category(name: 'بند الاختبار', isBuiltin: false, sortOrder: -1),
    );
    category = (await dao.getAllCategories(db)).firstWhere((c) => c.id == id);
    ayahs =
        (jsonDecode(
              await File('assets/quran/data/quran_data.json').readAsString(),
            ) as List)
            .map((a) => QuranAyah.fromJson(a as Map<String, dynamic>))
            .toList();
  });

  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });

  Future<void> assign(int id) => dao
      .assignVerseToCategory(
        db,
        surah: ayahs[id - 1].surah,
        ayah: ayahs[id - 1].ayah,
        categoryId: category.id!,
      )
      .then((_) {});

  Widget app(Widget home, {double scale = 1}) => MaterialApp(
    theme: ThemeData.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: home,
  );

  Future<void> openFromHome(WidgetTester tester) async {
    await tester.pumpWidget(app(HomeScreen(database: store)));
    final tile = find.byKey(ValueKey('home-category-${category.id}'));
    await waitReady(tester, () => tile.evaluate().isNotEmpty);
    await tester.tap(tile);
    await waitReady(
      tester,
      () =>
          find.byType(CategoryScreen).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  testWidgets(
    'custom category displays original verses in Quran order and empty builtin is clear',
    (tester) async {
      await tester.runAsync(() async {
        await assign(6236);
        await assign(1);
      });
      await openFromHome(tester);
      expect(find.text(ayahs.first.text), findsOneWidget);
      expect(find.text(ayahs.last.text), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('category-verse-1'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('category-verse-6236')))
              .dy,
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final builtin = (await tester.runAsync(() => dao.getAllCategories(db)))!
          .firstWhere((c) => c.isBuiltin);
      await tester.tap(find.byKey(ValueKey('home-category-${builtin.id}')));
      await waitReady(
        tester,
        () => find.text('لا توجد آيات في هذا البند بعد.').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'category to last verse is exact and Android Back restores category then home',
    (tester) async {
      await tester.runAsync(() async {
        await assign(6236);
        await dao.saveReadingProgress(db, surah: 2, ayah: 255);
        await dao.insertHighlight(
          db,
          const Highlight(
            surah: 114,
            ayah: 6,
            tokenStart: 0,
            tokenEnd: 0,
            colorHex: 'FFD700',
            createdAtMs: 1,
          ),
        );
      });
      await openFromHome(tester);
      await tester.tap(find.byKey(const ValueKey('category-verse-6236')));
      final target = find.byKey(const ValueKey('reader-verse-6236'));
      await waitReady(tester, () => target.evaluate().isNotEmpty);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('quran-scroll')),
      );
      expect(tester.getTopLeft(target).dy, closeTo(viewport.top, 1));
      expect(
        find.descendant(
          of: target,
          matching: find.textContaining(ayahs.last.text),
        ),
        findsOneWidget,
      );
      // Previous verses remain reachable above the exact target.
      await tester.drag(
        find.byKey(const ValueKey('quran-scroll')),
        const Offset(0, 250),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-verse-6235')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CategoryScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('category-verse-6236')), findsOneWidget);
      await tester.runAsync(() async {
        expect(await dao.getCategoryIdsForVerse(db, surah: 114, ayah: 6), [
          category.id,
        ]);
        expect((await dao.getReadingProgress(db))!.ayah, 255);
        expect(
          (await dao.getHighlightsForVerse(
            db,
            surah: 114,
            ayah: 6,
          )).single.colorHex,
          'FFD700',
        );
      });
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'category scroll position survives reader visit and removed membership refreshes',
    (tester) async {
      await tester.runAsync(() async {
        for (var id = 1; id <= 35; id++) {
          await assign(id);
        }
      });
      await openFromHome(tester);
      final list = find.byType(ListView);
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      final controller = tester.widget<ListView>(list).controller!;
      final before = controller.offset;
      final visible = find
          .byWidgetPredicate(
            (w) => w is InkWell && w.key.toString().contains('category-verse-'),
          )
          .hitTestable()
          .first;
      final key = tester.widget(visible).key! as ValueKey<String>;
      final id = int.parse(key.value.split('-').last);
      await tester.tap(visible);
      await waitReady(
        tester,
        () => find.byKey(ValueKey('reader-verse-$id')).evaluate().isNotEmpty,
      );
      await tester.binding.handlePopRoute();
      await waitReady(
        tester,
        () => find.byType(QuranReaderScreen).evaluate().isEmpty,
      );
      expect(controller.offset, closeTo(before, 1));
      await tester.tap(find.byKey(key));
      await waitReady(
        tester,
        () => find.byType(QuranReaderScreen).evaluate().isNotEmpty,
      );
      await tester.runAsync(
        () => dao.removeVerseFromCategory(
          db,
          surah: ayahs[id - 1].surah,
          ayah: ayahs[id - 1].ayah,
          categoryId: category.id!,
        ),
      );
      await tester.binding.handlePopRoute();
      await waitReady(
        tester,
        () =>
            find.byType(QuranReaderScreen).evaluate().isEmpty &&
            find.byKey(key).evaluate().isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final id in [1, 289, 3000, 6236]) {
    testWidgets(
      'reader targets verse $id exactly with narrow layout and large text',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            QuranReaderScreen(targetVerseId: id, database: store),
            scale: 1.5,
          ),
        );
        final target = find.byKey(ValueKey('reader-verse-$id'));
        await waitReady(tester, () => target.evaluate().isNotEmpty);
        // Layout can start more per-verse reads after the source is visible.
        await tester.runAsync(() => db.rawQuery('SELECT 1'));
        await tester.pump();
        expect(
          tester.getTopLeft(target).dy,
          closeTo(
            tester.getTopLeft(find.byKey(const ValueKey('quran-scroll'))).dy,
            1,
          ),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => db.rawQuery('SELECT 1'));
        await tester.pump();
      },
    );
  }
}
