/// AppDatabase — singleton SQLite database for all user data.
///
/// Quran data (quran_data.json) is NEVER stored here.
/// All tables reference Quran verses by (surah, ayah) integer pair only.
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Current schema version. Increment when tables change; add a migration in
/// [_migrate].
const int _kSchemaVersion = 1;

/// Database file name.  Must not change after first release.
const String _kDbName = 'user_data.db';

// ---------------------------------------------------------------------------
// Built-in categories seeded on first run
// ---------------------------------------------------------------------------

const List<Map<String, dynamic>> _kBuiltinCategories = [
  {'name': 'الفعل', 'is_builtin': 1, 'sort_order': 0},
  {'name': 'العمل', 'is_builtin': 1, 'sort_order': 1},
  {'name': 'المتقين', 'is_builtin': 1, 'sort_order': 2},
  {'name': 'الأسماء الحسنى', 'is_builtin': 1, 'sort_order': 3},
  {'name': 'النواهي', 'is_builtin': 1, 'sort_order': 4},
  {'name': 'الأوامر', 'is_builtin': 1, 'sort_order': 5},
  {'name': 'العقوبات', 'is_builtin': 1, 'sort_order': 6},
  {'name': 'الحمد', 'is_builtin': 1, 'sort_order': 7},
  {'name': 'الدعاء', 'is_builtin': 1, 'sort_order': 8},
  {'name': 'آيات محكمة', 'is_builtin': 1, 'sort_order': 9},
];

// ---------------------------------------------------------------------------
// AppDatabase
// ---------------------------------------------------------------------------

/// Singleton wrapper around the sqflite [Database].
///
/// Usage:
/// ```dart
/// final db = await AppDatabase.instance.database;
/// ```
class AppDatabase {
  AppDatabase._() : _factory = null, _path = null;

  /// Opens an isolated store using the same schema and seed data as the app.
  /// Useful for desktop tests without platform directory plugins.
  AppDatabase.atPath(String path, {required DatabaseFactory factory})
    : this._withFactory(path, factory);

  AppDatabase._withFactory(this._path, this._factory);

  final String? _path;
  final DatabaseFactory? _factory;
  static final AppDatabase instance = AppDatabase._();

  Future<Database>? _opening;

  /// Returns the open [Database], opening it on first call.
  Future<Database> get database {
    return _opening ??= _open().catchError((Object error, StackTrace stack) {
      _opening = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  /// Closes the database.  Useful in tests to reset state between runs.
  Future<void> close() async {
    final opening = _opening;
    if (opening == null) return;
    final db = await opening;
    await db.close();
    _opening = null;
  }

  // ---------------------------------------------------------------------------
  // Open / create / migrate
  // ---------------------------------------------------------------------------

  Future<Database> _open() async {
    final path =
        _path ??
        p.join((await getApplicationDocumentsDirectory()).path, _kDbName);

    return (_factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _kSchemaVersion,
        onCreate: _create,
        onUpgrade: _migrate,
        onConfigure: (db) async {
          // Enable foreign-key enforcement.
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }

  Future<void> _create(Database db, int version) async {
    await _createSchema(db);
    await _seedBuiltinCategories(db);
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    // Future migrations will be added here as numbered blocks.
    // e.g.:
    // if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    // ---- categories -------------------------------------------------------
    batch.execute('''
      CREATE TABLE categories (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL UNIQUE,
        is_builtin  INTEGER NOT NULL DEFAULT 0,
        sort_order  INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ---- verse_categories -------------------------------------------------
    batch.execute('''
      CREATE TABLE verse_categories (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        surah         INTEGER NOT NULL,
        ayah          INTEGER NOT NULL,
        category_id   INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
        created_at_ms INTEGER NOT NULL,
        UNIQUE(surah, ayah, category_id)
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_vc_category ON verse_categories(category_id)
    ''');
    batch.execute('''
      CREATE INDEX idx_vc_verse ON verse_categories(surah, ayah)
    ''');

    // ---- highlights -------------------------------------------------------
    // token_start / token_end are whitespace-delimited word indices (0-based).
    // Using word tokens instead of char offsets is safe with Arabic grapheme
    // clusters, diacritics, and Quranic symbols.
    batch.execute('''
      CREATE TABLE highlights (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        surah         INTEGER NOT NULL,
        ayah          INTEGER NOT NULL,
        token_start   INTEGER NOT NULL,
        token_end     INTEGER NOT NULL,
        color_hex     TEXT    NOT NULL,
        created_at_ms INTEGER NOT NULL,
        CHECK(token_start >= 0),
        CHECK(token_end   >= token_start)
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_hl_verse ON highlights(surah, ayah)
    ''');

    // ---- reading_progress -------------------------------------------------
    // Only one row (id = 1).
    batch.execute('''
      CREATE TABLE reading_progress (
        id            INTEGER PRIMARY KEY,
        surah         INTEGER NOT NULL,
        ayah          INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    // ---- settings ---------------------------------------------------------
    batch.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // ---- notes ------------------------------------------------------------
    batch.execute('''
      CREATE TABLE notes (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        surah         INTEGER,
        ayah          INTEGER,
        content       TEXT    NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_notes_verse ON notes(surah, ayah)
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> _seedBuiltinCategories(Database db) async {
    final batch = db.batch();
    for (final cat in _kBuiltinCategories) {
      batch.insert(
        'categories',
        cat,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }
}
