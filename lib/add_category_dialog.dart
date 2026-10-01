import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'database/user_data_dao.dart';

class AddCategoryDialog extends StatefulWidget {
  const AddCategoryDialog({
    super.key,
    required this.database,
    required this.surah,
    required this.ayah,
  });

  final Database database;
  final int surah;
  final int ayah;

  @override
  State<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<AddCategoryDialog> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'أدخل اسم البند.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await const UserDataDao().createCategoryForVerse(
        widget.database,
        name: _name.text,
        surah: widget.surah,
        ayah: widget.ayah,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is DatabaseException && error.isUniqueConstraintError()
              ? 'يوجد بند بهذا الاسم. اختر اسماً آخر.'
              : 'تعذر إنشاء البند. حاول مرة أخرى.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E222A),
        title: const Text('إضافة بند'),
        content: TextField(
          controller: _name,
          autofocus: true,
          enabled: !_saving,
          textDirection: TextDirection.rtl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'اسم البند',
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
          ),
        ],
      ),
    ),
  );
}
