import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'database/user_data_models.dart';
import 'quran_reader_screen.dart';
import 'quran_repository.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.category, this.database});

  final Category category;
  final AppDatabase? database;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _scroll = ScrollController();
  Future<List<QuranAyah>>? _quran;
  List<QuranAyah> _ayahs = [];
  List<int> _verseIds = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ayahs = await (_quran ??= QuranRepository().loadAyahs());
      final db = await (widget.database ?? AppDatabase.instance).database;
      final links = await const UserDataDao().getVersesForCategory(
        db,
        categoryId: widget.category.id!,
      );
      final indices = <(int, int), int>{
        for (var i = 0; i < ayahs.length; i++)
          (ayahs[i].surah, ayahs[i].ayah): i + 1,
      };
      final ids = <int>[];
      for (final link in links) {
        final id = indices[(link.surah, link.ayah)];
        if (id == null) throw StateError('Invalid verse reference');
        ids.add(id);
      }
      if (!mounted) return;
      setState(() {
        _ayahs = ayahs;
        _verseIds = ids;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      _quran = null;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _openVerse(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            QuranReaderScreen(targetVerseId: id, database: widget.database),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF121212),
    appBar: AppBar(title: Text(widget.category.name), centerTitle: true),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('تعذر تحميل آيات البند.'),
                TextButton(
                  onPressed: _load,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          )
        : _verseIds.isEmpty
        ? const Center(child: Text('لا توجد آيات في هذا البند بعد.'))
        : ListView.separated(
            key: PageStorageKey('category-${widget.category.id}'),
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: _verseIds.length,
            separatorBuilder: (_, index) =>
                const Divider(color: Color(0xFF2A2D34)),
            itemBuilder: (context, index) {
              final id = _verseIds[index];
              final ayah = _ayahs[id - 1];
              return InkWell(
                key: ValueKey('category-verse-$id'),
                onTap: () => _openVerse(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    ayah.text,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 2.1,
                      color: Color(0xFFECEFF1),
                    ),
                  ),
                ),
              );
            },
          ),
  );
}
