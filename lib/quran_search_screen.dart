import 'package:flutter/material.dart';
import 'quran_repository.dart';
import 'quran_search_service.dart';
import 'quran_reader_screen.dart';

class QuranSearchScreen extends StatefulWidget {
  const QuranSearchScreen({super.key});

  @override
  State<QuranSearchScreen> createState() => _QuranSearchScreenState();
}

class _QuranSearchScreenState extends State<QuranSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final QuranSearchService _searchService = QuranSearchService();
  final QuranRepository _repository = QuranRepository();

  List<SearchResult> _results = [];
  bool _isInitializing = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _ensureIndexReady();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensureIndexReady() async {
    if (!_searchService.isReady) {
      setState(() => _isInitializing = true);
      try {
        final ayahs = await _repository.loadAyahs();
        await _searchService.initIndex(ayahs);
      } catch (e) {
        // Handle error silently or show snackbar
      } finally {
        if (mounted) {
          setState(() => _isInitializing = false);
          if (_currentQuery.isNotEmpty) {
            _onSearchChanged(_currentQuery);
          }
        }
      }
    }
  }

  void _onSearchChanged(String query) {
    _currentQuery = query;
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
      });
      return;
    }

    final results = _searchService.search(query);
    setState(() {
      _results = results;
    });
  }

  void _navigateToAyah(SearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuranReaderScreen(
          targetVerseId: result.verseId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16181B),
        elevation: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: const Color(0xFF90CAF9),
          decoration: InputDecoration(
            hintText: 'ابحث في آيات القرآن الكريم...',
            hintStyle: const TextStyle(color: Color(0xFF78909C), fontSize: 15),
            hintTextDirection: TextDirection.rtl,
            border: InputBorder.none,
            suffixIcon: _currentQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF78909C), size: 20),
                    onPressed: () {
                      _controller.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF90CAF9),
              strokeWidth: 2.5,
            ),
            SizedBox(height: 16),
            Text(
              'جاري تجهيز فهرس البحث...',
              style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_currentQuery.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.search, size: 64, color: Color(0xFF263238)),
            SizedBox(height: 12),
            Text(
              'اكتب أي كلمة أو جزء منها للبحث الفوري',
              style: TextStyle(color: Color(0xFF78909C), fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56, color: Color(0xFF374151)),
            const SizedBox(height: 12),
            Text(
              'لا توجد نتائج مطابقة لـ "$_currentQuery"',
              style: const TextStyle(color: Color(0xFF78909C), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF16181B),
          child: Text(
            'عدد النتائج: ${_results.length}',
            style: const TextStyle(color: Color(0xFF78909C), fontSize: 13),
            textDirection: TextDirection.rtl,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (context, index) => const Divider(
              color: Color(0xFF1E222A),
              height: 1,
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final result = _results[index];
              return _buildResultTile(result);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultTile(SearchResult result) {
    // Note: Per requirement 10 and PROJECT_SPEC.md Section 7:
    // "Do NOT show surah name. Do NOT show ayah number."
    // Only show the short matching excerpt with matching text highlighted.
    return InkWell(
      onTap: () => _navigateToAyah(result),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.9,
                    color: Color(0xFFB0BEC5),
                  ),
                  children: [
                    if (result.hasLeadingEllipsis)
                      const TextSpan(
                        text: '... ',
                        style: TextStyle(color: Color(0xFF546E7A)),
                      ),
                    TextSpan(text: result.excerptPrefix),
                    TextSpan(
                      text: result.excerptMatch,
                      style: const TextStyle(
                        color: Color(0xFF90CAF9),
                        fontWeight: FontWeight.bold,
                        backgroundColor: Color(0xFF15293E),
                      ),
                    ),
                    TextSpan(text: result.excerptSuffix),
                    if (result.hasTrailingEllipsis)
                      const TextSpan(
                        text: ' ...',
                        style: TextStyle(color: Color(0xFF546E7A)),
                      ),
                  ],
                ),
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.chevron_left,
              color: Color(0xFF455A64),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
