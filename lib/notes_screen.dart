import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'database/user_data_models.dart';
import 'note_editor_screen.dart';
import 'quran_reader_screen.dart';
import 'quran_repository.dart';

/// With a verse reference, shows only that verse's notes and allows creation.
/// Without one, shows all saved notes. Quran text is never stored here.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, this.surah, this.ayah, this.database})
    : assert((surah == null) == (ayah == null));

  final int? surah;
  final int? ayah;
  final AppDatabase? database;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  static const _dao = UserDataDao();
  List<Note> _notes = [];
  bool _loading = true;
  bool _error = false;
  bool _opening = false;
  Future<List<QuranAyah>>? _quran;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await (widget.database ?? AppDatabase.instance).database;
      final notes = widget.surah == null
          ? await _dao.getAllNotes(db)
          : await _dao.getNotesForVerse(
              db,
              surah: widget.surah!,
              ayah: widget.ayah!,
            );
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _edit([Note? note]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(
          surah: note?.surah ?? widget.surah,
          ayah: note?.ayah ?? widget.ayah,
          note: note,
          database: widget.database,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openVerse(Note note) async {
    if (_opening) return;
    if (note.surah == null || note.ayah == null) return _edit(note);
    setState(() => _opening = true);
    try {
      // Resolve the existing logical reference only when opening a verse.
      final ayahs = await (_quran ??= QuranRepository().loadAyahs());
      final index = ayahs.indexWhere(
        (a) => a.surah == note.surah && a.ayah == note.ayah,
      );
      if (index < 0) throw StateError('Invalid verse reference');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QuranReaderScreen(
            targetVerseId: index + 1,
            database: widget.database,
          ),
        ),
      );
      if (mounted) await _load();
    } catch (_) {
      _quran = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الآية. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.surah == null ? 'ملاحظات' : 'ملاحظات الآية'),
        centerTitle: true,
      ),
      floatingActionButton: widget.surah == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة ملاحظة'),
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.surah != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(noteReference(widget.surah, widget.ayah)),
              ),
            if (_opening) const LinearProgressIndicator(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('تعذر تحميل الملاحظات.'),
                          TextButton(
                            onPressed: _load,
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    )
                  : _notes.isEmpty
                  ? const Center(child: Text('لا توجد ملاحظات محفوظة بعد.'))
                  : ListView.separated(
                      key: PageStorageKey(
                        'notes-${widget.surah}-${widget.ayah}',
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: _notes.length,
                      separatorBuilder: (_, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return ListTile(
                          key: ValueKey('note-${note.id}'),
                          title: Text(
                            note.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(noteReference(note.surah, note.ayah)),
                          onTap: _opening ? null : () => _openVerse(note),
                          trailing: IconButton(
                            key: ValueKey('edit-note-${note.id}'),
                            tooltip: 'تعديل الملاحظة',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(note),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
