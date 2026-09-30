import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// SQLite (WAL) storage. Uses Drift's isolate-backed executor with hand-written
/// SQL so hot paths (FTS5 search, keyset pagination, 10k-row bulk upsert) stay
/// under our control and need no code generation.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  static Future<AppDatabase> open(String path) async {
    final executor = NativeDatabase.createInBackground(
      File(path),
      setup: (raw) {
        raw.execute('PRAGMA journal_mode = WAL;');
        raw.execute('PRAGMA synchronous = NORMAL;');
        raw.execute('PRAGMA foreign_keys = ON;');
        raw.execute('PRAGMA temp_store = MEMORY;');
      },
    );
    return AppDatabase(executor);
  }

  /// In-memory database for tests.
  static AppDatabase memory() => AppDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        raw.execute('PRAGMA foreign_keys = ON;');
      },
    ),
  );

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final s in _schemaV1) {
        await customStatement(s);
      }
    },
    onUpgrade: (m, from, to) async {
      // Future migrations go here: each step is `if (from < N) {...}`.
    },
  );

  // ---- generic helpers -----------------------------------------------------

  Future<List<Map<String, Object?>>> query(
    String sqlText, [
    List<Object?> args = const [],
  ]) async {
    final rows = await customSelect(
      sqlText,
      variables: args.map(Variable.new).toList(),
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<void> exec(String sqlText, [List<Object?> args = const []]) =>
      customStatement(sqlText, args);

  // ---- key/value settings --------------------------------------------------

  Future<String?> kvGet(String key) async {
    final r = await query('SELECT value FROM kv WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> kvSet(String key, String value) => exec(
    'INSERT INTO kv(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

  Future<void> kvDelete(String key) =>
      exec('DELETE FROM kv WHERE key = ?', [key]);
}

const _schemaV1 = <String>[
  'CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  '''CREATE TABLE profiles(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      url TEXT,
      user_agent TEXT NOT NULL DEFAULT '',
      auto_refresh INTEGER NOT NULL DEFAULT 1,
      interval_hours INTEGER NOT NULL DEFAULT 24,
      updated_at INTEGER,
      upload INTEGER NOT NULL DEFAULT 0,
      download INTEGER NOT NULL DEFAULT 0,
      total INTEGER NOT NULL DEFAULT 0,
      expire INTEGER NOT NULL DEFAULT 0,
      last_error TEXT NOT NULL DEFAULT '',
      fail_count INTEGER NOT NULL DEFAULT 0,
      sort INTEGER NOT NULL DEFAULT 0
    )''',
  '''CREATE TABLE nodes(
      rowid INTEGER PRIMARY KEY AUTOINCREMENT,
      id TEXT NOT NULL,
      profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      protocol TEXT NOT NULL,
      server TEXT NOT NULL,
      port INTEGER NOT NULL,
      latency INTEGER NOT NULL DEFAULT -1,
      alive INTEGER NOT NULL DEFAULT 1,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      group_tag TEXT NOT NULL DEFAULT '',
      requires TEXT NOT NULL DEFAULT '',
      raw_enc TEXT NOT NULL,
      seen INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      UNIQUE(profile_id, id)
    )''',
  'CREATE INDEX idx_nodes_profile_latency ON nodes(profile_id, latency)',
  'CREATE INDEX idx_nodes_protocol ON nodes(protocol)',
  'CREATE INDEX idx_nodes_server ON nodes(server)',
  'CREATE INDEX idx_nodes_id ON nodes(id)',
  // Trigram FTS5 index => fast substring search over name + server.
  '''CREATE VIRTUAL TABLE nodes_fts USING fts5(
      name, server, content='nodes', content_rowid='rowid', tokenize='trigram')''',
  '''CREATE TRIGGER nodes_ai AFTER INSERT ON nodes BEGIN
      INSERT INTO nodes_fts(rowid, name, server) VALUES (new.rowid, new.name, new.server);
    END''',
  '''CREATE TRIGGER nodes_ad AFTER DELETE ON nodes BEGIN
      INSERT INTO nodes_fts(nodes_fts, rowid, name, server) VALUES('delete', old.rowid, old.name, old.server);
    END''',
  '''CREATE TRIGGER nodes_au AFTER UPDATE OF name, server ON nodes BEGIN
      INSERT INTO nodes_fts(nodes_fts, rowid, name, server) VALUES('delete', old.rowid, old.name, old.server);
      INSERT INTO nodes_fts(rowid, name, server) VALUES (new.rowid, new.name, new.server);
    END''',
];
