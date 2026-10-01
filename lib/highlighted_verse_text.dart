import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'database/user_data_models.dart';
import 'highlight_editor.dart';
import 'quran_repository.dart';
import 'quran_tokens.dart';

/// Adds backgrounds to exact source slices. Concatenating the spans is always
/// identical to the source (including spacing, marks and Quranic symbols).
List<TextSpan> highlightedSpans(
  QuranTokens tokens,
  List<Highlight> highlights,
) {
  final valid =
      highlights
          .where(
            (h) =>
                tokens.containsRange(h.tokenStart, h.tokenEnd) &&
                RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(h.colorHex),
          )
          .toList()
        ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final token in tokens.words) {
    if (cursor < token.start) {
      spans.add(TextSpan(text: tokens.source.substring(cursor, token.start)));
    }
    Highlight? active;
    for (final h in valid) {
      if (h.tokenStart <= token.id && h.tokenEnd >= token.id) active = h;
    }
    spans.add(
      TextSpan(
        text: tokens.word(token.id),
        style: active == null
            ? null
            : TextStyle(
                backgroundColor: Color(
                  int.parse('FF${active.colorHex}', radix: 16),
                ),
                color: const Color(0xFF121212),
              ),
      ),
    );
    cursor = token.end;
  }
  if (cursor < tokens.source.length) {
    spans.add(TextSpan(text: tokens.source.substring(cursor)));
  }
  return spans;
}

class HighlightedVerseText extends StatefulWidget {
  const HighlightedVerseText({
    super.key,
    required this.ayah,
    required this.numberLabel,
    this.database,
  });
  final QuranAyah ayah;
  final String numberLabel;
  final AppDatabase? database;

  @override
  State<HighlightedVerseText> createState() => _HighlightedVerseTextState();
}

class _HighlightedVerseTextState extends State<HighlightedVerseText> {
  final _textKey = GlobalKey();
  late final _tokens = QuranTokens(widget.ayah.text);
  List<Highlight> _highlights = [];
  bool _error = false;
  bool _editing = false;
  int _request = 0;
  AppDatabase get _database => widget.database ?? AppDatabase.instance;
  static const _dao = UserDataDao();

  @override
  void initState() {
    super.initState();
    highlightChanges.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    highlightChanges.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final db = await _database.database;
      final data = await _dao.getHighlightsForVerse(
        db,
        surah: widget.ayah.surah,
        ayah: widget.ayah.ayah,
      );
      if (mounted && request == _request) {
        setState(() {
          _highlights = data;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    }
  }

  void _longPress(LongPressStartDetails details) {
    final paragraph = _textKey.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return;
    final point = paragraph.globalToLocal(details.globalPosition);
    // Hit-test complete source token boxes: never select part of a combining
    // cluster, whitespace outside a word, or the appended ayah number.
    for (final token in _tokens.words) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: token.start, extentOffset: token.end),
      );
      if (boxes.any((box) => box.toRect().contains(point))) {
        _edit(token.id);
        return;
      }
    }
  }

  Future<void> _edit(int token) async {
    if (_editing) return;
    _editing = true;
    await _load();
    if (!mounted) return;
    if (_error) {
      _editing = false;
      return;
    }
    final existing =
        _highlights
            .where(
              (h) =>
                  _tokens.containsRange(h.tokenStart, h.tokenEnd) &&
                  h.tokenStart <= token &&
                  h.tokenEnd >= token,
            )
            .toList()
          ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1D23),
      builder: (_) => HighlightEditor(
        tokens: _tokens,
        surah: widget.ayah.surah,
        ayah: widget.ayah.ayah,
        tokenId: token,
        database: _database,
        existing: existing.isEmpty ? null : existing.last,
      ),
    );
    if (mounted) {
      _editing = false;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        hint: 'اضغط مطولاً على كلمة لتظليلها',
        onLongPress: _tokens.words.isEmpty ? null : () => _edit(0),
        child: GestureDetector(
          onLongPressStart: _longPress,
          child: Text.rich(
            key: _textKey,
            TextSpan(
              style: const TextStyle(
                color: Color(0xFFECEFF1),
                fontSize: 21,
                height: 2.1,
                fontWeight: FontWeight.w400,
              ),
              children: [
                ...highlightedSpans(_tokens, _highlights),
                TextSpan(
                  text: widget.numberLabel,
                  style: const TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.justify,
            textDirection: TextDirection.rtl,
          ),
        ),
      ),
      if (_error)
        TextButton(
          onPressed: _load,
          child: const Text('تعذر تحميل التظليل. إعادة المحاولة'),
        ),
    ],
  );
}
