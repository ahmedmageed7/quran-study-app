import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';
import 'package:quran_app/home_screen.dart';
import 'package:quran_app/quran_reader_screen.dart';
import 'package:quran_app/quran_search_screen.dart';

Future<void> ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Timed out waiting for reader storage');
}

void main() {
  late Directory temp;
  late AppDatabase store;
  late Database db;
  const dao = UserDataDao();
  final scroll = find.byKey(const ValueKey('quran-scroll'));
  Finder verse(int id) => find.byKey(ValueKey('reader-verse-$id'));
  setUp(() async {
    rootBundle.evict('assets/quran/data/quran_data.json');
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('reading_progress_');
    store = AppDatabase.atPath(
      p.join(temp.path, 'user.db'),
      factory: databaseFactoryFfi,
    );
    db = await store.database;
  });
  tearDown(() async {
    await store.close();
    await temp.delete(recursive: true);
  });

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: HomeScreen(database: store),
      ),
    );
    await ready(
      tester,
      () => find.text('متابعة القراءة').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('متابعة القراءة'));
    await ready(tester, () => scroll.evaluate().isNotEmpty);
  }

  testWidgets(
    'Home resumes exact saved verse; Back saves visible verse and disk reopen restores it',
    (tester) async {
      await tester.runAsync(
        () => dao.saveReadingProgress(db, surah: 2, ayah: 10),
      );
      await launch(tester);
      expect(
        tester.getTopLeft(verse(17)).dy,
        closeTo(tester.getTopLeft(scroll).dy, 1),
      );
      // Use actual layout to place the next verse partially above the viewport.
      final controller = tester.widget<CustomScrollView>(scroll).controller!;
      final distance =
          tester.getTopLeft(verse(18)).dy - tester.getTopLeft(scroll).dy;
      controller.jumpTo(distance + 12);
      await tester.pump();
      // Android Back before the debounce must still flush to SQLite.
      await tester.binding.handlePopRoute();
      await ready(
        tester,
        () => find.byType(QuranReaderScreen).evaluate().isEmpty,
      );
      final saved = (await tester.runAsync(() => dao.getReadingProgress(db)))!;
      expect(saved.surah, 2);
      expect(saved.ayah, 11);
      await tester.runAsync(() => store.close());
      db = (await tester.runAsync(() => store.database))!;
      await tester.tap(find.text('متابعة القراءة'));
      await ready(tester, () => scroll.evaluate().isNotEmpty);
      expect(
        tester.getTopLeft(verse(18)).dy,
        closeTo(tester.getTopLeft(scroll).dy, 1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('idle scroll and lifecycle pause persist actual visible verse', (
    tester,
  ) async {
    await launch(tester);
    final controller = tester.widget<CustomScrollView>(scroll).controller!;
    controller.jumpTo(
      tester.getTopLeft(verse(3)).dy - tester.getTopLeft(scroll).dy + 8,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    final saved = (await tester.runAsync(() => dao.getReadingProgress(db)))!;
    expect((saved.surah, saved.ayah), (1, 3));
    controller.jumpTo(
      controller.offset +
          tester.getTopLeft(verse(4)).dy -
          tester.getTopLeft(scroll).dy +
          8,
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    final paused = (await tester.runAsync(() => dao.getReadingProgress(db)))!;
    expect((paused.surah, paused.ayah), (1, 4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Search target scroll never overwrites reading progress and Back retains query and reader offset',
    (tester) async {
      await tester.runAsync(
        () => dao.saveReadingProgress(db, surah: 2, ayah: 10),
      );
      await launch(tester);
      final controller = tester.widget<CustomScrollView>(scroll).controller!;
      controller.jumpTo(25);
      await tester.pump();
      await tester.tap(find.byTooltip('البحث في القرآن'));
      await ready(
        tester,
        () =>
            find.byType(QuranSearchScreen).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      final saved = (await tester.runAsync(() => dao.getReadingProgress(db)))!;
      await tester.enterText(find.byType(TextField), 'الصمد');
      await tester.pumpAndSettle();
      final result = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(InkWell),
      );
      expect(result, findsOneWidget);
      await tester.tap(result);
      await ready(tester, () => verse(6223).evaluate().isNotEmpty);
      expect(
        tester.getTopLeft(verse(6223)).dy,
        closeTo(tester.getTopLeft(scroll).dy, 1),
      );
      await tester.drag(scroll, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'الصمد',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<CustomScrollView>(scroll).controller!.offset, 25);
      final after = (await tester.runAsync(() => dao.getReadingProgress(db)))!;
      expect(
        (after.surah, after.ayah, after.updatedAtMs),
        (saved.surah, saved.ayah, saved.updatedAtMs),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
