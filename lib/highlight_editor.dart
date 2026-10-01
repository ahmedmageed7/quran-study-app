import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'database/user_data_models.dart';
import 'quran_tokens.dart';

const highlightColors = <String, String>{
  'FFD54F': 'أصفر',
  '81C784': 'أخضر',
  '64B5F6': 'أزرق',
  'F48FB1': 'وردي',
};

/// Invalidates mounted verse views, including readers underneath another route.
final highlightChanges = ValueNotifier<int>(0);

class HighlightEditor extends StatefulWidget {
  const HighlightEditor({
    super.key,
    required this.tokens,
    required this.surah,
    required this.ayah,
    required this.tokenId,
    required this.database,
    this.existing,
  });
  final QuranTokens tokens;
  final int surah;
  final int ayah;
  final int tokenId;
  final AppDatabase database;
  final Highlight? existing;

  @override
  State<HighlightEditor> createState() => _HighlightEditorState();
}

class _HighlightEditorState extends State<HighlightEditor> {
  late int _start = widget.existing?.tokenStart ?? widget.tokenId;
  late int _end = widget.existing?.tokenEnd ?? widget.tokenId;
  bool _busy = false;
  String? _error;
  static const _dao = UserDataDao();

  Future<void> _save(String? color) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = await widget.database.database;
      if (color == null) {
        await _dao.deleteHighlight(db, widget.existing!.id!);
      } else {
        await _dao.saveHighlight(
          db,
          Highlight(
            id: widget.existing?.id,
            surah: widget.surah,
            ayah: widget.ayah,
            tokenStart: _start,
            tokenEnd: _end,
            colorHex: color,
            createdAtMs:
                widget.existing?.createdAtMs ??
                DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
          wordCount: widget.tokens.words.length,
        );
      }
      highlightChanges.value++;
      if (mounted) Navigator.pop(context);
    } on HighlightOverlapException {
      if (mounted) {
        setState(
          () => _error = 'يتداخل النطاق مع تظليل آخر. اختر نطاقاً آخر أو عدّل التظليل الموجود.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر حفظ التظليل. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _rangeField(bool start) => InputDecorator(
    decoration: InputDecoration(labelText: start ? 'من كلمة' : 'إلى كلمة'),
    child: DropdownButton<int>(
      key: ValueKey(start ? 'highlight-start' : 'highlight-end'),
      value: start ? _start : _end,
      isExpanded: true,
      items: [
        for (final word in widget.tokens.words)
          DropdownMenuItem(
            value: word.id,
            child: Text(
              '${word.id + 1}. ${widget.tokens.word(word.id)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _busy
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                if (start) {
                  _start = value;
                  if (_end < value) _end = value;
                } else {
                  _end = value;
                  if (_start > value) _start = value;
                }
              });
            },
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existing == null ? 'تظليل الكلمات' : 'تعديل التظليل',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                // Keep the selected source visible even when its verse is
                // behind the sheet. Do not scroll the reader or alter progress.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 96),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.tokens.range(_start, _end),
                      key: const ValueKey('highlight-source-preview'),
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 21, height: 2.1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _rangeField(true),
                const SizedBox(height: 8),
                _rangeField(false),
                const SizedBox(height: 16),
                const Text('اختر اللون للحفظ'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in highlightColors.entries)
                      FilledButton(
                        key: ValueKey('highlight-color-${color.key}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Color(
                            int.parse('FF${color.key}', radix: 16),
                          ),
                          foregroundColor: Colors.black,
                          minimumSize: const Size(64, 48),
                        ),
                        onPressed: _busy ? null : () => _save(color.key),
                        child: Text(color.value),
                      ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.existing != null)
                      TextButton.icon(
                        key: const ValueKey('highlight-delete'),
                        onPressed: _busy ? null : () => _save(null),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('إزالة التظليل'),
                      ),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
