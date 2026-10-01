import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'database/user_data_models.dart';

String noteReference(int? surah, int? ayah) =>
    surah == null || ayah == null ? 'ملاحظة عامة' : 'سورة $surah • آية $ayah';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.surah,
    required this.ayah,
    this.note,
    this.database,
  });

  final int? surah;
  final int? ayah;
  final Note? note;
  final AppDatabase? database;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final _text = TextEditingController(text: widget.note?.content ?? '');
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _allowPop = false;
  bool _confirming = false;
  String? _error;
  static const _dao = UserDataDao();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<bool> _confirm(String title, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ),
      ) ??
      false;

  Future<void> _back() async {
    if (_busy || _confirming) return;
    _confirming = true;
    final unchanged = _text.text == (widget.note?.content ?? '');
    if (unchanged || await _confirm('تجاهل التغييرات غير المحفوظة؟', 'تجاهل')) {
      _close();
    }
    _confirming = false;
  }

  Future<void> _save({bool delete = false}) async {
    if (_busy || _confirming) return;
    if (delete) {
      _confirming = true;
      final confirmed = await _confirm('حذف هذه الملاحظة؟', 'حذف');
      _confirming = false;
      if (!confirmed || !mounted) return;
    } else if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = await (widget.database ?? AppDatabase.instance).database;
      final note = widget.note;
      if (delete) {
        await _dao.deleteNote(db, note!.id!);
      } else if (note != null) {
        final count = await _dao.updateNote(
          db,
          noteId: note.id!,
          content: _text.text.trim(),
        );
        if (count != 1) throw StateError('Note no longer exists');
      } else {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await _dao.insertNote(
          db,
          Note(
            surah: widget.surah,
            ayah: widget.ayah,
            content: _text.text.trim(),
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
      }
      _close();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذر حفظ التغيير. بقي النص هنا؛ حاول مرة أخرى.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.note == null ? 'إضافة ملاحظة' : 'تعديل الملاحظة'),
          actions: [
            if (widget.note != null)
              IconButton(
                tooltip: 'حذف الملاحظة',
                onPressed: _busy ? null : () => _save(delete: true),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(noteReference(widget.surah, widget.ayah)),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('note-content'),
                  controller: _text,
                  readOnly: _busy,
                  minLines: 5,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'الملاحظة',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'اكتب الملاحظة قبل الحفظ.'
                      : null,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                FilledButton(
                  key: const ValueKey('save-note'),
                  onPressed: _busy ? null : () => _save(),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
