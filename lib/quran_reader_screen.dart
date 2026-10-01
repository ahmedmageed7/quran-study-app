import 'dart:async';

import 'package:flutter/material.dart';

import 'quran_repository.dart';
import 'database/app_database.dart';
import 'database/user_data_dao.dart';
import 'reader_verse_anchor.dart';
import 'highlighted_verse_text.dart';
import 'verse_category_menu.dart';
import 'quran_search_screen.dart';
import 'notes_screen.dart';

class QuranReaderScreen extends StatefulWidget {
  final int? targetVerseId;
  final AppDatabase? database;

  const QuranReaderScreen({super.key, this.targetVerseId, this.database});

  @override
  State<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends State<QuranReaderScreen>
    with WidgetsBindingObserver {
  static List<QuranAyah>? _cachedAyahs;
  final QuranRepository _repository = QuranRepository();
  final ScrollController _scrollController = ScrollController();

  List<QuranAyah> _ayahs = _cachedAyahs ?? [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _highlightedVerseId;
  final Key _centerSliver = UniqueKey();
  final _viewportKey = GlobalKey();
  final Map<int, RenderBox> _verseBoxes = {};
  static const _dao = UserDataDao();
  // Serialize writes, including a final write from a departing reader, before
  // another normal reader loads the saved position.
  static Future<void>? _progressWrites;
  Timer? _saveTimer;
  bool _framePending = false;
  bool _dirty = false;
  bool _allowPop = false;
  bool _leaving = false;
  int _originIndex = 0;
  int _visibleIndex = 0;
  bool get _tracksProgress => widget.targetVerseId == null;

  static const List<String> _surahNames = [
    'الفاتحة',
    'البقرة',
    'آل عمران',
    'النساء',
    'المائدة',
    'الأنعام',
    'الأعراف',
    'الأنفال',
    'التوبة',
    'يونس',
    'هود',
    'يوسف',
    'الرعد',
    'إبراهيم',
    'الحجر',
    'النحل',
    'الإسراء',
    'الكهف',
    'مريم',
    'طه',
    'الأنبياء',
    'الحج',
    'المؤمنون',
    'النور',
    'الفرقان',
    'الشعراء',
    'النمل',
    'القصص',
    'العنكبوت',
    'الروم',
    'لقمان',
    'السجدة',
    'الأحزاب',
    'سبأ',
    'فاطر',
    'يس',
    'الصافات',
    'ص',
    'الزمر',
    'غافر',
    'فصلت',
    'الشورى',
    'الزخرف',
    'الدخان',
    'الجاثية',
    'الأحقاف',
    'محمد',
    'الفتح',
    'الحجرات',
    'ق',
    'الذاريات',
    'الطور',
    'النجم',
    'القمر',
    'الرحمن',
    'الواقعة',
    'الحديد',
    'المجادلة',
    'الحشر',
    'الممتحنة',
    'الصف',
    'الجمعة',
    'المنافقون',
    'التغابن',
    'الطلاق',
    'التحريم',
    'الملك',
    'القلم',
    'الحاقة',
    'المعارج',
    'نوح',
    'الجن',
    'المزمل',
    'المدثر',
    'القيامة',
    'الإنسان',
    'المرسلات',
    'النبأ',
    'النازعات',
    'عبس',
    'التكوير',
    'الانفطار',
    'المطففين',
    'الانشقاق',
    'البروج',
    'الطارق',
    'الأعلى',
    'الغاشية',
    'الفجر',
    'البلد',
    'الشمس',
    'الليل',
    'الضحى',
    'الشرح',
    'التين',
    'العلق',
    'القدر',
    'البينة',
    'الزلزلة',
    'العاديات',
    'القارعة',
    'التكاثر',
    'العصر',
    'الهمزة',
    'الفيل',
    'قريش',
    'الماعون',
    'الكوثر',
    'الكافرون',
    'النصر',
    'المسد',
    'الإخلاص',
    'الفلق',
    'الناس',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _highlightedVerseId = widget.targetVerseId;
    _loadQuran();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    unawaited(_flushProgress());
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadQuran() async {
    try {
      final loaded = _cachedAyahs ?? await _repository.loadAyahs();
      _cachedAyahs = loaded;
      var origin = (widget.targetVerseId ?? 1) - 1;
      if (_tracksProgress) {
        if (_progressWrites != null) await _progressWrites;
        final db = await (widget.database ?? AppDatabase.instance).database;
        final progress = await _dao.getReadingProgress(db);
        if (progress != null) {
          origin = loaded.indexWhere(
            (a) => a.surah == progress.surah && a.ayah == progress.ayah,
          );
        }
      }
      if (origin < 0 || origin >= loaded.length) origin = 0;
      if (mounted) {
        setState(() {
          _ayahs = loaded;
          _originIndex = origin;
          _visibleIndex = origin;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذر تحميل بيانات القرآن: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _captureVisibleVerse() {
    if (!_tracksProgress ||
        _isLoading ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    int? first;
    var firstTop = double.infinity;
    for (final entry in _verseBoxes.entries) {
      final box = entry.value;
      if (!box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height > top + 1 && y < bottom && y < firstTop) {
        first = entry.key;
        firstTop = y;
      }
    }
    if (first != null && first != _visibleIndex) {
      _visibleIndex = first;
      _dirty = true;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_tracksProgress || notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      if (!_framePending) {
        _framePending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _framePending = false;
          if (!mounted) return;
          _captureVisibleVerse();
          _saveTimer?.cancel();
          _saveTimer = Timer(
            const Duration(milliseconds: 350),
            () => unawaited(_flushProgress()),
          );
        });
      }
    }
    return false;
  }

  Future<void> _flushProgress() {
    _saveTimer?.cancel();
    if (!_tracksProgress || !_dirty || _ayahs.isEmpty) {
      return _progressWrites ?? Future<void>.value();
    }
    final ayah = _ayahs[_visibleIndex];
    final database = widget.database ?? AppDatabase.instance;
    _dirty = false;
    final write = (_progressWrites ?? Future<void>.value()).then((_) async {
      try {
        final db = await database.database;
        await _dao.saveReadingProgress(db, surah: ayah.surah, ayah: ayah.ayah);
      } catch (_) {
        if (mounted) {
          _dirty = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر حفظ موضع القراءة. حاول مرة أخرى.'),
            ),
          );
        }
      }
    });
    _progressWrites = write;
    return write.whenComplete(() {
      if (identical(_progressWrites, write)) _progressWrites = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _captureVisibleVerse();
      unawaited(_flushProgress());
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _captureVisibleVerse();
    await _flushProgress();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String _toArabicDigits(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number.toString().split('').map((char) {
      final digit = int.tryParse(char);
      return digit != null ? arabicDigits[digit] : char;
    }).join();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_tracksProgress || _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF16181B),
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'القرآن الكريم',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search, color: Color(0xFF90A4AE)),
              tooltip: 'البحث في القرآن',
              onPressed: () async {
                _captureVisibleVerse();
                await _flushProgress();
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const QuranSearchScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF90CAF9),
          strokeWidth: 2.5,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Scrollbar(
        controller: _scrollController,
        interactive: true,
        thickness: 4.0,
        radius: const Radius.circular(8),
        child: SizedBox(
          key: _viewportKey,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              key: const ValueKey('quran-scroll'),
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              center: _centerSliver,
              slivers: [
                // The target is the scroll origin. Earlier verses grow upwards;
                // later verses grow downwards using their real laid-out heights.
                SliverList.builder(
                  itemCount: _targetIndex,
                  itemBuilder: (context, index) =>
                      _buildVerse(_targetIndex - index - 1),
                ),
                SliverList.builder(
                  key: _centerSliver,
                  itemCount: _ayahs.length - _targetIndex,
                  itemBuilder: (context, index) =>
                      _buildVerse(_targetIndex + index),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get _targetIndex {
    return _originIndex;
  }

  Widget _buildVerse(int index) {
    final ayah = _ayahs[index];
    return ReaderVerseAnchor(
      key: ValueKey('reader-verse-${index + 1}'),
      index: index,
      onAttach: (id, box) => _verseBoxes[id] = box,
      onDetach: (id) => _verseBoxes.remove(id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ayah.ayah == 1) _buildSurahHeader(ayah.surah),
          _buildAyahTile(ayah, index),
        ],
      ),
    );
  }

  Widget _buildSurahHeader(int surahNumber) {
    final name = (surahNumber >= 1 && surahNumber <= _surahNames.length)
        ? _surahNames[surahNumber - 1]
        : '$surahNumber';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D23),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2B303A)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'سورة $name',
              style: const TextStyle(
                color: Color(0xFFECEFF1),
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'سورة رقم ${_toArabicDigits(surahNumber)}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFF78909C),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAyahTile(QuranAyah ayah, int index) {
    final isTarget = _highlightedVerseId == index + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 3.0),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: isTarget
          ? BoxDecoration(
              color: const Color(0xFF152A3E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF64B5F6), width: 1.5),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: HighlightedVerseText(
              key: ValueKey('highlight-text-${ayah.surah}-${ayah.ayah}'),
              ayah: ayah,
              numberLabel: ' ﴿${_toArabicDigits(ayah.ayah)}﴾ ',
              database: widget.database,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              _buildCategoryMenuButton(ayah),
              IconButton(
                key: ValueKey('verse-notes-${ayah.surah}-${ayah.ayah}'),
                tooltip: 'ملاحظات الآية',
                icon: const Icon(
                  Icons.note_alt_outlined,
                  size: 18,
                  color: Color(0xFF90A4AE),
                ),
                onPressed: () async {
                  _captureVisibleVerse();
                  await _flushProgress();
                  if (!mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NotesScreen(
                        surah: ayah.surah,
                        ayah: ayah.ayah,
                        database: widget.database,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryMenuButton(QuranAyah ayah) => VerseCategoryMenu(
    key: ValueKey('verse-categories-${ayah.surah}-${ayah.ayah}'),
    surah: ayah.surah,
    ayah: ayah.ayah,
    database: widget.database,
  );
}
