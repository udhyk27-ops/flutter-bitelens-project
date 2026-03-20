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
      version: 1,
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
      },
    );
  }

  // 저장
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

  // 전체 목록 조회
  Future<List<Map<String, dynamic>>> getAnalysisHistory() async {
    final db = await database;
    return await db.query(
      'analysis_history',
      orderBy: 'created_at DESC',
    );
  }

  // 삭제
  Future<void> deleteAnalysis(int id) async {
    final db = await database;
    await db.delete('analysis_history', where: 'id = ?', whereArgs: [id]);
  }

  // 전체 삭제
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('analysis_history');
  }
}