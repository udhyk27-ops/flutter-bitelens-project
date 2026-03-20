import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bitelens.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE analysis_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            image_path TEXT NOT NULL,
            food_name TEXT,
            calories TEXT,
            result TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE weight_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            weight REAL NOT NULL,
            logged_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS weight_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              weight REAL NOT NULL,
              logged_at TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  // ─── analysis_history ────────────────────────────────────

  Future<int> insertAnalysis({
    required String imagePath,
    required String result,
  }) async {
    final db = await database;
    return await db.insert('analysis_history', {
      'image_path': imagePath,
      'result': result,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAnalysisHistory() async {
    final db = await database;
    return await db.query('analysis_history', orderBy: 'created_at DESC');
  }

  Future<void> deleteAnalysis(int id) async {
    final db = await database;
    await db.delete('analysis_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('analysis_history');
  }

  // ─── weight_log ──────────────────────────────────────────

  /// 몸무게 기록 추가
  Future<int> insertWeight(double weight) async {
    final db = await database;
    return await db.insert('weight_log', {
      'weight': weight,
      'logged_at': DateTime.now().toIso8601String(),
    });
  }

  /// 전체 몸무게 기록 조회 (오래된 순)
  Future<List<Map<String, dynamic>>> getWeightLog() async {
    final db = await database;
    return await db.query('weight_log', orderBy: 'logged_at ASC');
  }

  /// 몸무게 기록 삭제
  Future<void> deleteWeight(int id) async {
    final db = await database;
    await db.delete('weight_log', where: 'id = ?', whereArgs: [id]);
  }

  /// 몸무게 기록 전체 삭제
  Future<void> clearWeightLog() async {
    final db = await database;
    await db.delete('weight_log');
  }
}