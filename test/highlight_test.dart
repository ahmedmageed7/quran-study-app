import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';
import 'package:quran_app/database/user_data_models.dart';
import 'package:quran_app/highlight_editor.dart';
import 'package:quran_app/highlighted_verse_text.dart';
import 'package:quran_app/quran_reader_screen.dart';
import 'package:quran_app/quran_tokens.dart';

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
  fail('Timed out waiting for highlight UI');
}

void main() {
  late Directory temp;
  late AppDatabase store;
  late Database db;
  const dao = UserDataDao();
  final source = File('assets/quran/data/quran_data.json');
  Highlight make(int start, int end, {String color = 'FFD54F', int? id}) =>
      Highlight(
        id: id,
        surah: 1,
        ayah: 1,
        tokenStart: start,
        tokenEnd: end,
        colorHex: color,
        createdAtMs: 123,
      );

  setUp(() async {
    rootBundle.evict('assets/quran/data/quran_data.json');
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('highlights_');
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

  test('all source ayahs retain exact UTF-16 and stable existing word IDs after rendering', () async {
    final data = jsonDecode(await source.readAsString()) as List;
    expect(data.length, 6236);
    for (final row in data) {
      final text = row['text'] as String;
      final tokens = QuranTokens(text);
      final oldWords = RegExp(r'\S+').allMatches(text).toList();
      expect(tokens.words.length, oldWords.length);
      for (final token in tokens.words) {
        expect(tokens.word(token.id), oldWords[token.id].group(0));
      }
      final spans = highlightedSpans(tokens, [
        make(0, tokens.words.length - 1),
      ]);
      expect(TextSpan(children: spans).toPlainText().codeUnits, text.codeUnits);
    }
  });

  test('combining marks, Quranic signs, repeated whitespace and surrogate pairs remain exact', () {
    const text = '  بِسْمِ\tٱللَّهِ  ۞\nرَبِّۦ 𝄞  ';
    final tokens = QuranTokens(text);
    expect(tokens.words.map((t) => t.id), [0, 1, 2, 3, 4]);
    expect(make(0, 1).selectedText(text), 'بِسْمِ\tٱللَّهِ');
    expect(make(2, 4).selectedText(text), '۞\nرَبِّۦ 𝄞');
    expect(
      TextSpan(
        children: highlightedSpans(tokens, [
          make(0, 1),
          make(3, 4, color: '64B5F6'),
        ]),
      ).toPlainText(),
      text,
    );
    expect(() => tokens.range(0, 5), throwsRangeError);
  });

  test('single and multiple word highlights persist; editing/deleting leaves source and other user data unchanged', () async {
    final bytes = await source.readAsBytes();
    final category = (await dao.getAllCategories(db)).first;
    await dao.assignVerseToCategory(
      db,
      surah: 1,
      ayah: 1,
      categoryId: category.id!,
    );
    await dao.saveReadingProgress(db, surah: 2, ayah: 255);
    final progress = (await dao.getReadingProgress(db))!.toMap();
    await dao.saveHighlight(db, make(0, 0), wordCount: 4);
    await dao.saveHighlight(db, make(2, 3, color: '64B5F6'), wordCount: 4);
    await store.close();
    db = await store.database;
    var saved = await dao.getHighlightsForVerse(db, surah: 1, ayah: 1);
    expect(saved.map((h) => (h.tokenStart, h.tokenEnd, h.colorHex)), [
      (0, 0, 'FFD54F'),
      (2, 3, '64B5F6'),
    ]);
    await dao.saveHighlight(
      db,
      make(0, 0, id: saved.first.id, color: '81C784'),
      wordCount: 4,
    );
    saved = await dao.getHighlightsForVerse(db, surah: 1, ayah: 1);
    expect(saved.first.colorHex, '81C784');
    await dao.deleteHighlight(db, saved.first.id!);
    expect(
      (await dao.getHighlightsForVerse(db, surah: 1, ayah: 1)).single.id,
      saved.last.id,
    );
    expect(await dao.getCategoryIdsForVerse(db, surah: 1, ayah: 1), [
      category.id,
    ]);
    expect((await dao.getReadingProgress(db))!.toMap(), progress);
    expect(await source.readAsBytes(), bytes);
  });

  test('overlap and invalid ranges/colors are rejected without changing saved highlights', () async {
    await dao.saveHighlight(db, make(1, 2), wordCount: 4);
    await expectLater(
      dao.saveHighlight(db, make(0, 1), wordCount: 4),
      throwsA(isA<HighlightOverlapException>()),
    );
    for (final h in [
      make(-1, 1),
      make(3, 2),
      make(0, 4),
      make(0, 0, color: 'oops'),
    ]) {
      await expectLater(
        dao.saveHighlight(db, h, wordCount: 4),
        throwsArgumentError,
      );
    }
    expect((await dao.getHighlightsForVerse(db, surah: 1, ayah: 1)).length, 1);
  });

  Finder verse() => find.byKey(const ValueKey('highlight-text-1-1'));
  Finder rich() =>
      find.descendant(of: verse(), matching: find.byType(RichText)).first;
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: QuranReaderScreen(targetVerseId: 1, database: store),
      ),
    );
    await ready(tester, () => verse().evaluate().isNotEmpty);
  }

  Future<void> press(WidgetTester tester, int token) async {
    final paragraph = tester.renderObject<RenderParagraph>(rich());
    final text = paragraph.text.toPlainText();
    final word = QuranTokens(text).words[token];
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        )
        .first
        .toRect();
    await tester.longPressAt(paragraph.localToGlobal(box.center));
    await ready(
      tester,
      () => find.byType(HighlightEditor).evaluate().isNotEmpty,
    );
  }

  List<TextSpan> spans(WidgetTester tester) =>
      ((tester
                      .widget<Text>(
                        find
                            .descendant(
                              of: verse(),
                              matching: find.byType(Text),
                            )
                            .first,
                      )
                      .textSpan
                  as TextSpan)
              .children!)
          .cast<TextSpan>();

  Future<void> color(WidgetTester tester, String hex) async {
    await tester.tap(find.byKey(ValueKey('highlight-color-$hex')));
    await ready(tester, () => find.byType(HighlightEditor).evaluate().isEmpty);
    await ready(
      tester,
      () => spans(tester).any(
        (s) =>
            s.style?.backgroundColor == Color(int.parse('FF$hex', radix: 16)),
      ),
    );
  }

  testWidgets(
    'long press creates single word, expands range, adds second color, restores, edits and deletes',
    (tester) async {
      await launch(tester);
      final original = tester.widget<RichText>(rich()).text.toPlainText();
      final originalSize = tester.getSize(rich());
      await press(tester, 0);
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('highlight-start')),
            )
            .value,
        0,
      );
      await color(tester, 'FFD54F');
      expect(
        spans(tester).first.style!.backgroundColor,
        const Color(0xFFFFD54F),
      );
      await press(tester, 0);
      await tester.tap(find.byKey(const ValueKey('highlight-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2. ٱللَّهِ').last);
      await tester.pumpAndSettle();
      await color(tester, '81C784');
      await press(tester, 2);
      await color(tester, '64B5F6');
      var saved = (await tester.runAsync(
        () => dao.getHighlightsForVerse(db, surah: 1, ayah: 1),
      ))!;
      expect(saved.map((h) => (h.tokenStart, h.tokenEnd, h.colorHex)), [
        (0, 1, '81C784'),
        (2, 2, '64B5F6'),
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.close());
      db = (await tester.runAsync(() => store.database))!;
      await launch(tester);
      await ready(
        tester,
        () => spans(tester).first.style?.backgroundColor != null,
      );
      expect(
        spans(tester).first.style!.backgroundColor,
        const Color(0xFF81C784),
      );
      expect(tester.widget<RichText>(rich()).text.toPlainText(), original);
      expect(tester.getSize(rich()), originalSize);
      await press(tester, 0);
      await tester.tap(find.byKey(const ValueKey('highlight-delete')));
      await ready(
        tester,
        () => find.byType(HighlightEditor).evaluate().isEmpty,
      );
      saved = (await tester.runAsync(
        () => dao.getHighlightsForVerse(db, surah: 1, ayah: 1),
      ))!;
      expect(saved.single.tokenStart, 2);
      expect(spans(tester).first.style, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed save shows retry; cancellation and ayah number do not create highlights',
    (tester) async {
      await launch(tester);
      final paragraph = tester.renderObject<RenderParagraph>(rich());
      final text = paragraph.text.toPlainText();
      final number = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: text.indexOf('﴿'),
              extentOffset: text.indexOf('﴾') + 1,
            ),
          )
          .first
          .toRect();
      await tester.longPressAt(paragraph.localToGlobal(number.center));
      await tester.pumpAndSettle();
      expect(find.byType(HighlightEditor), findsNothing);
      await press(tester, 0);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => dao.getHighlightsForVerse(db, surah: 1, ayah: 1),
        ),
        isEmpty,
      );
      await tester.runAsync(
        () => db.execute(
          "CREATE TRIGGER fail_highlight BEFORE INSERT ON highlights BEGIN SELECT RAISE(ABORT, 'test'); END",
        ),
      );
      await press(tester, 0);
      await tester.tap(find.byKey(const ValueKey('highlight-color-FFD54F')));
      await ready(
        tester,
        () =>
            find.text('تعذر حفظ التظليل. حاول مرة أخرى.').evaluate().isNotEmpty,
      );
      expect(spans(tester).first.style, isNull);
      await tester.runAsync(() => db.execute('DROP TRIGGER fail_highlight'));
      await color(tester, 'FFD54F');
      expect(
        spans(tester).first.style!.backgroundColor,
        const Color(0xFFFFD54F),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
