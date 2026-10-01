import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quran_app/database/app_database.dart';
import 'package:quran_app/database/user_data_dao.dart';
import 'package:quran_app/database/user_data_models.dart';
import 'package:quran_app/home_screen.dart';
import 'package:quran_app/note_editor_screen.dart';
import 'package:quran_app/notes_screen.dart';
import 'package:quran_app/quran_reader_screen.dart';

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
  fail('Notes UI timed out');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase store;
  late Database db;
  const dao = UserDataDao();
  Note make(String text, {int? surah = 112, int? ayah = 2}) => Note(
    surah: surah,
    ayah: ayah,
    content: text,
    createdAtMs: 123,
    updatedAtMs: 123,
  );

  setUp(() async {
    rootBundle.evict('assets/quran/data/quran_data.json');
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('notes_');
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

  test('notes create, update, multiple per verse and persist with unchanged references', () async {
    final id = await dao.insertNote(db, make('تأمّل شخصيّ ۞'));
    await dao.insertNote(db, make('ملاحظة ثانية'));
    await dao.insertNote(db, make('آية أخرى', ayah: 3));
    expect(
      await dao.updateNote(db, noteId: id, content: 'تعديل شخصيّ\nسطر ثانٍ'),
      1,
    );
    await store.close();
    db = await store.database;
    final notes = await dao.getNotesForVerse(db, surah: 112, ayah: 2);
    expect(notes.length, 2);
    final edited = notes.firstWhere((n) => n.id == id);
    expect(edited.content, 'تعديل شخصيّ\nسطر ثانٍ');
    expect(edited.createdAtMs, 123);
    expect(edited.updatedAtMs, greaterThan(123));
    expect(edited.surah, 112);
    expect(edited.ayah, 2);
    expect(await dao.getNotesForVerse(db, surah: 1, ayah: 2), isEmpty);
    expect((await dao.getAllNotes(db)).length, 3);
    expect(await dao.deleteNote(db, id), 1);
    await store.close();
    expect((await dao.getAllNotes(await store.database)).length, 2);
  });

  test(
    'empty notes and partial references rejected without losing saved content',
    () async {
      final id = await dao.insertNote(db, make('محفوظة'));
      await expectLater(dao.insertNote(db, make(' \n ')), throwsArgumentError);
      await expectLater(
        dao.updateNote(db, noteId: id, content: '  '),
        throwsArgumentError,
      );
      await expectLater(
        dao.insertNote(db, make('نص', ayah: null)),
        throwsArgumentError,
      );
      expect((await dao.getAllNotes(db)).single.content, 'محفوظة');
    },
  );

  test('deleting note preserves exact Quran bytes, highlights, categories and progress', () async {
    final source = File('assets/quran/data/quran_data.json');
    final original = await source.readAsBytes();
    final category = (await dao.getAllCategories(db)).first.id!;
    await dao.assignVerseToCategory(
      db,
      surah: 112,
      ayah: 2,
      categoryId: category,
    );
    await dao.saveHighlight(
      db,
      const Highlight(
        surah: 112,
        ayah: 2,
        tokenStart: 0,
        tokenEnd: 0,
        colorHex: '81C784',
        createdAtMs: 1,
      ),
      wordCount: 2,
    );
    await dao.saveReadingProgress(db, surah: 2, ayah: 255);
    final highlights = (await dao.getHighlightsForVerse(
      db,
      surah: 112,
      ayah: 2,
    )).map((h) => h.toMap()).toList();
    final progress = (await dao.getReadingProgress(db))!.toMap();
    final id = await dao.insertNote(db, make('ملاحظة للحذف'));
    await dao.deleteNote(db, id);
    expect(await dao.getAllNotes(db), isEmpty);
    expect(
      (await dao.getHighlightsForVerse(
        db,
        surah: 112,
        ayah: 2,
      )).map((h) => h.toMap()),
      highlights,
    );
    expect(await dao.getCategoryIdsForVerse(db, surah: 112, ayah: 2), [
      category,
    ]);
    expect((await dao.getReadingProgress(db))!.toMap(), progress);
    expect(await source.readAsBytes(), original);
  });

  Future<void> launch(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(480, 900),
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: page,
      ),
    );
  }

  testWidgets(
    'Reader creates and edits note; Home opens exact verse; Back preserves other user data',
    (tester) async {
      await tester.runAsync(() async {
        await dao.saveReadingProgress(db, surah: 112, ayah: 2);
        await dao.assignVerseToCategory(db, surah: 112, ayah: 2, categoryId: 1);
        await dao.saveHighlight(
          db,
          const Highlight(
            surah: 112,
            ayah: 2,
            tokenStart: 0,
            tokenEnd: 0,
            colorHex: '81C784',
            createdAtMs: 1,
          ),
          wordCount: 2,
        );
      });
      final progress = (await tester.runAsync(
        () => dao.getReadingProgress(db),
      ))!.toMap();
      await launch(tester, HomeScreen(database: store));
      await ready(
        tester,
        () => find.text('متابعة القراءة').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('متابعة القراءة'));
      final noteButton = find.byKey(const ValueKey('verse-notes-112-2'));
      await ready(tester, () => noteButton.evaluate().isNotEmpty);
      final scroll = find.byKey(const ValueKey('quran-scroll'));
      final offset = tester.widget<CustomScrollView>(scroll).controller!.offset;
      await tester.tap(noteButton);
      await ready(
        tester,
        () => find.text('لا توجد ملاحظات محفوظة بعد.').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('إضافة ملاحظة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-note')));
      await tester.pump();
      expect(find.text('اكتب الملاحظة قبل الحفظ.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('note-content')),
        'تأمّل للآية',
      );
      await tester.tap(find.byKey(const ValueKey('save-note')));
      await ready(
        tester,
        () =>
            find.text('تأمّل للآية').evaluate().isNotEmpty &&
            find.byType(NoteEditorScreen).evaluate().isEmpty,
      );
      final note = (await tester.runAsync(() => dao.getAllNotes(db)))!.single;
      expect((note.surah, note.ayah), (112, 2));
      await tester.tap(find.byKey(ValueKey('edit-note-${note.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note-content')),
        'تأمّل معدّل',
      );
      await tester.tap(find.byKey(const ValueKey('save-note')));
      await ready(
        tester,
        () =>
            find.text('تأمّل معدّل').evaluate().isNotEmpty &&
            find.byType(NoteEditorScreen).evaluate().isEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<CustomScrollView>(scroll).controller!.offset,
        offset,
      );
      await tester.binding.handlePopRoute();
      await ready(
        tester,
        () => find.byType(QuranReaderScreen).evaluate().isEmpty,
      );
      await tester.ensureVisible(find.text('ملاحظات'));
      await tester.tap(find.text('ملاحظات'));
      await ready(
        tester,
        () => find.byKey(ValueKey('note-${note.id}')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(ValueKey('note-${note.id}')));
      await ready(tester, () => noteButton.evaluate().isNotEmpty);
      final reader = tester.widget<QuranReaderScreen>(
        find.byType(QuranReaderScreen),
      );
      expect(reader.targetVerseId, 6223);
      final paragraph = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('highlight-text-112-2')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(
        ((paragraph.textSpan as TextSpan).children!.first as TextSpan)
            .style!
            .backgroundColor,
        const Color(0xFF81C784),
      );
      await tester.drag(scroll, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await ready(
        tester,
        () => find.byKey(ValueKey('note-${note.id}')).evaluate().isNotEmpty,
      );
      expect(
        (await tester.runAsync(() => dao.getReadingProgress(db)))!.toMap(),
        progress,
      );
      expect(
        await tester.runAsync(
          () => dao.getCategoryIdsForVerse(db, surah: 112, ayah: 2),
        ),
        [1],
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unsaved Android Back confirmation and confirmed delete return to empty notes',
    (tester) async {
      final id = (await tester.runAsync(
        () => dao.insertNote(db, make('محفوظة')),
      ))!;
      await launch(tester, NotesScreen(database: store));
      await ready(
        tester,
        () => find.byKey(ValueKey('edit-note-$id')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(ValueKey('edit-note-$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note-content')),
        'غير محفوظة',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('تجاهل التغييرات غير المحفوظة؟'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('note-content')))
            .controller!
            .text,
        'غير محفوظة',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('تجاهل'));
      await ready(
        tester,
        () => find.byType(NoteEditorScreen).evaluate().isEmpty,
      );
      expect(
        (await tester.runAsync(() => dao.getAllNotes(db)))!.single.content,
        'محفوظة',
      );
      await tester.tap(find.byKey(ValueKey('edit-note-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('حذف الملاحظة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      await ready(
        tester,
        () => find.text('لا توجد ملاحظات محفوظة بعد.').evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => dao.getAllNotes(db)), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(375, 667), const Size(667, 375)]) {
    testWidgets(
      'note editor is scrollable with keyboard and large text at $size',
      (tester) async {
        await launch(
          tester,
          const NoteEditorScreen(surah: 2, ayah: 255),
          size: size,
          scale: 2,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('note-content')),
          'سطر\nثانٍ\nثالث',
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('save-note')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('save-note')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
