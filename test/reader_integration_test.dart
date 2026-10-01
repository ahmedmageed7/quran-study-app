import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';
import 'package:quran_app/highlight_editor.dart';
import 'package:quran_app/home_screen.dart';
import 'package:quran_app/quran_reader_screen.dart';
import 'package:quran_app/quran_search_screen.dart';
import 'package:quran_app/quran_tokens.dart';

Future<void> ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  fail('Reader integration timed out');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Database db;
  late int categoryId;
  const dao = UserDataDao();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final store = AppDatabase.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  final scroll = find.byKey(const ValueKey('quran-scroll'));
  final verse = find.byKey(const ValueKey('highlight-text-112-2'));
  final categoryButton = find.descendant(
    of: find.byKey(const ValueKey('verse-categories-112-2')),
    matching: find.byType(IconButton),
  );
  final editor = find.byType(HighlightEditor);
  final paragraphFinder = find
      .descendant(of: verse, matching: find.byType(RichText))
      .first;
  Finder category() => find.byKey(ValueKey('category-$categoryId'));

  setUp(() async {
    rootBundle.evict('assets/quran/data/quran_data.json');
    temp = await Directory.systemTemp.createTemp('reader_integration_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => temp.path);
    db = await store.database;
    categoryId = (await dao.getAllCategories(db)).first.id!;
    await dao.saveReadingProgress(db, surah: 112, ayah: 2);
  });
  tearDown(() async {
    await store.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await temp.delete(recursive: true);
  });

  Color? displayedColor(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(of: verse, matching: find.byType(Text)).first,
    );
    return ((text.textSpan as TextSpan).children!.first as TextSpan)
        .style
        ?.backgroundColor;
  }

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const HomeScreen(),
      ),
    );
    await ready(
      tester,
      () => find.text('متابعة القراءة').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('متابعة القراءة'));
    await ready(tester, () => verse.evaluate().isNotEmpty);
  }

  Future<void> pressWord(WidgetTester tester) async {
    final paragraph = tester.renderObject<RenderParagraph>(paragraphFinder);
    final token = QuranTokens(paragraph.text.toPlainText()).words.first;
    final rect = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: token.start, extentOffset: token.end),
        )
        .first
        .toRect();
    await tester.longPressAt(paragraph.localToGlobal(rect.center));
    await ready(tester, () => editor.evaluate().isNotEmpty);
    expect(category().evaluate(), isEmpty);
  }

  Future<void> highlight(WidgetTester tester, String hex) async {
    await pressWord(tester);
    await tester.tap(find.byKey(ValueKey('highlight-color-$hex')));
    await ready(
      tester,
      () =>
          editor.evaluate().isEmpty &&
          displayedColor(tester) == Color(int.parse('FF$hex', radix: 16)),
    );
  }

  Future<void> classify(WidgetTester tester) async {
    await tester.tap(categoryButton);
    await ready(tester, () => category().evaluate().isNotEmpty);
    expect(editor, findsNothing);
    await tester.tap(category());
    await ready(
      tester,
      () =>
          category().evaluate().isEmpty &&
          tester.widget<IconButton>(categoryButton).onPressed != null,
    );
  }

  for (final highlightFirst in [true, false]) {
    testWidgets(
      '${highlightFirst ? 'Highlight then category' : 'Category then highlight'} survives Search editing, Back and cold reopen independently',
      (tester) async {
        final progress = (await tester.runAsync(
          () => dao.getReadingProgress(db),
        ))!.toMap();
        await launch(tester);
        if (highlightFirst) {
          await highlight(tester, 'FFD54F');
          await classify(tester);
        } else {
          await classify(tester);
          await highlight(tester, 'FFD54F');
        }
        expect(
          await tester.runAsync(
            () => dao.getCategoryIdsForVerse(db, surah: 112, ayah: 2),
          ),
          [categoryId],
        );
        await tester.tap(find.byTooltip('البحث في القرآن'));
        await ready(
          tester,
          () =>
              find.byType(QuranSearchScreen).evaluate().isNotEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
        await tester.enterText(find.byType(TextField), 'الصمد');
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(InkWell),
              )
              .first,
        );
        await ready(tester, () => verse.evaluate().isNotEmpty);
        await highlight(tester, '81C784');
        await tester.tap(categoryButton);
        await ready(tester, () => category().evaluate().isNotEmpty);
        expect(
          tester.widget<CheckedPopupMenuItem<int>>(category()).checked,
          isTrue,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.drag(scroll, const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(editor, findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'الصمد',
        );
        await tester.binding.handlePopRoute();
        await ready(
          tester,
          () =>
              verse.evaluate().isNotEmpty &&
              displayedColor(tester) == const Color(0xFF81C784),
        );
        expect(tester.widget<CustomScrollView>(scroll).controller!.offset, 0);
        await tester.binding.handlePopRoute();
        await ready(
          tester,
          () => find.byType(QuranReaderScreen).evaluate().isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => store.close());
        db = (await tester.runAsync(() => store.database))!;
        await launch(tester);
        await ready(
          tester,
          () => displayedColor(tester) == const Color(0xFF81C784),
        );
        expect(
          await tester.runAsync(
            () => dao.getCategoryIdsForVerse(db, surah: 112, ayah: 2),
          ),
          [categoryId],
        );
        expect(
          (await tester.runAsync(() => dao.getReadingProgress(db)))!.toMap(),
          progress,
        );
        expect(
          (await tester.runAsync(
            () => dao.getHighlightsForVerse(db, surah: 112, ayah: 2),
          ))!.single.colorHex,
          '81C784',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'highlight sheet previews lower-screen source without moving reader; Back dismisses only sheet and drag stays scroll',
    (tester) async {
      await launch(tester);
      final controller = tester.widget<CustomScrollView>(scroll).controller!;
      controller.jumpTo(-380);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final progress = (await tester.runAsync(
        () => dao.getReadingProgress(db),
      ))!.toMap();
      final offset = controller.offset;
      await pressWord(tester);
      final preview = find.byKey(const ValueKey('highlight-source-preview'));
      expect(preview.hitTestable(), findsOneWidget);
      expect(tester.widget<Text>(preview).data, 'ٱللَّهُ');
      expect(controller.offset, offset);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(find.byType(QuranReaderScreen), findsOneWidget);
      expect(
        (await tester.runAsync(() => dao.getReadingProgress(db)))!.toMap(),
        progress,
      );
      await tester.drag(paragraphFinder, const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(controller.offset, isNot(offset));
      await tester.binding.handlePopRoute();
      await ready(
        tester,
        () => find.byType(QuranReaderScreen).evaluate().isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
