import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'add_category_dialog.dart';

/// Reads category membership afresh on every opening. No reader-local cache.
class VerseCategoryMenu extends StatefulWidget {
  const VerseCategoryMenu({
    super.key,
    required this.surah,
    required this.ayah,
    this.database,
  });

  final int surah;
  final int ayah;
  final AppDatabase? database;

  @override
  State<VerseCategoryMenu> createState() => _VerseCategoryMenuState();
}

class _VerseCategoryMenuState extends State<VerseCategoryMenu> {
  static const _dao = UserDataDao();
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    var saving = false;
    var reopen = false;
    try {
      final db = await (widget.database ?? AppDatabase.instance).database;
      final categories = await _dao.getAllCategories(db);
      final selected = await _dao.getCategoryIdsForVerse(
        db,
        surah: widget.surah,
        ayah: widget.ayah,
      );
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final button = context.findRenderObject()! as RenderBox;
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()!
              as RenderBox;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
      final categoryId = await showMenu<int>(
        context: context,
        position: position,
        color: const Color(0xFF1E222A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF2C323D)),
        ),
        items: [
          for (final category in categories)
            CheckedPopupMenuItem<int>(
              key: ValueKey('category-${category.id}'),
              value: category.id,
              checked: selected.contains(category.id),
              height: 38,
              child: Text(category.name, style: const TextStyle(fontSize: 14)),
            ),
          const PopupMenuItem<int>(
            value: 0,
            height: 38,
            child: Text('إضافة بند', style: TextStyle(fontSize: 14)),
          ),
        ],
      );
      if (categoryId == null) return;
      if (categoryId == 0) {
        if (!mounted) return;
        reopen =
            await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => AddCategoryDialog(
                database: db,
                surah: widget.surah,
                ayah: widget.ayah,
              ),
            ) ??
            false;
      } else {
        saving = true;
        // Complete an explicitly selected write even if the reader is closed.
        await _dao.toggleVerseCategory(
          db,
          surah: widget.surah,
          ayah: widget.ayah,
          categoryId: categoryId,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saving
                  ? 'تعذر حفظ التصنيف. حاول مرة أخرى.'
                  : 'تعذر تحميل التصنيفات. حاول مرة أخرى.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (reopen && mounted) await _open();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 36,
    child: IconButton(
      tooltip: 'تصنيفات الآية',
      padding: EdgeInsets.zero,
      onPressed: _busy ? null : _open,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert, size: 18, color: Color(0xFF78909C)),
    ),
  );
}
