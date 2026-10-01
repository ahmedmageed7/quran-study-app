import 'package:flutter/material.dart';

import 'quran_reader_screen.dart';
import 'quran_search_screen.dart';
import 'category_screen.dart';
import 'notes_screen.dart';
import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'database/user_data_models.dart';

class _CategoryItem {
  final String title;
  final IconData icon;
  final bool isAdd;
  final Category? category;

  const _CategoryItem(
    this.title,
    this.icon, {
    this.isAdd = false,
    this.category,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.database});
  final AppDatabase? database;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Category> _savedCategories = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final db = await (widget.database ?? AppDatabase.instance).database;
      final categories = await const UserDataDao().getAllCategories(db);
      if (mounted) {
        setState(() {
          _savedCategories = categories;
          _loading = false;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _loadCategories();
  }

  static const List<_CategoryItem> _categoryStyles = [
    _CategoryItem('الفعل', Icons.bolt_outlined),
    _CategoryItem('العمل', Icons.handyman_outlined),
    _CategoryItem('المتقين', Icons.shield_outlined),
    _CategoryItem('الأسماء الحسنى', Icons.auto_awesome_outlined),
    _CategoryItem('النواهي', Icons.block_outlined),
    _CategoryItem('الأوامر', Icons.check_circle_outline),
    _CategoryItem('العقوبات', Icons.gavel_outlined),
    _CategoryItem('الحمد', Icons.favorite_border_rounded),
    _CategoryItem('الدعاء', Icons.front_hand_outlined),
    _CategoryItem('آيات محكمة', Icons.balance_outlined),
    _CategoryItem('إضافة بند', Icons.add_rounded, isAdd: true),
  ];

  List<_CategoryItem> get _categories => [
    for (final category in _savedCategories)
      _CategoryItem(
        category.name,
        _categoryStyles
            .firstWhere(
              (item) => item.title == category.name,
              orElse: () => const _CategoryItem('', Icons.label_outline),
            )
            .icon,
        category: category,
      ),
    _categoryStyles.last,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تطبيق القرآن',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF90A4AE)),
            tooltip: 'البحث في القرآن',
            onPressed: () {
              _openPage(const QuranSearchScreen());
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildQuranCard(context),
            const SizedBox(height: 20),
            _buildSectionTitle('البنود'),
            const SizedBox(height: 12),
            _buildCategoriesGrid(),
            const SizedBox(height: 20),
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuranCard(BuildContext context) {
    return InkWell(
      onTap: () {
        _openPage(QuranReaderScreen(database: widget.database));
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E2D3D), Color(0xFF15222E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E4057)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'القرآن الكريم',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: const [
                      Icon(
                        Icons.auto_stories_outlined,
                        color: Color(0xFF90CAF9),
                        size: 15,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'متابعة القراءة',
                        style: TextStyle(
                          color: Color(0xFFB0BEC5),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildCategoriesGrid() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return Column(
        children: [
          const Text('تعذر تحميل البنود.'),
          TextButton(
            onPressed: _loadCategories,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      );
    }
    final categories = _categories;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.8,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final item = categories[index];
        final isAdd = item.isAdd;

        return InkWell(
          key: ValueKey('home-category-${item.category?.id ?? 'add'}'),
          onTap: () {
            if (item.category != null) {
              _openPage(
                CategoryScreen(
                  category: item.category!,
                  database: widget.database,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isAdd ? const Color(0xFF141619) : const Color(0xFF1B1D21),
              border: Border.all(
                color: isAdd ? Colors.white24 : const Color(0xFF2A2D34),
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: isAdd ? Colors.white70 : const Color(0xFF90A4AE),
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      color: isAdd ? Colors.white70 : Colors.white,
                      fontSize: 14,
                      fontWeight: isAdd ? FontWeight.normal : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionTile(
            title: 'ملاحظات',
            icon: Icons.note_alt_outlined,
            onTap: () {
              _openPage(NotesScreen(database: widget.database));
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildActionTile(
            title: 'الإعدادات',
            icon: Icons.settings_outlined,
            onTap: () {
              // Action later
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1D21),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2D34)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF90A4AE), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
