import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static const _databaseName = "MyDatabase.db";
  static const _databaseVersion = 1;

  static const table = 'my_table';

  static const columnId = 'id';
  static const columnName = 'name';
  static const columnEmbedding = 'embedding';
  static const columnImage = 'image';


  Database? _db;
  Future<void> init() async {
    if (_db != null && _db!.isOpen) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    _db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL,
        $columnEmbedding TEXT NOT NULL,
        $columnImage BLOB NOT NULL
      )
    ''');
  }

  Future<int> insert(Map<String, dynamic> row) async {
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.insert(table, row);
  }

  Future<List<Map<String, dynamic>>> queryAllRows() async {
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.query(table);
  }

  Future<int> queryRowCount() async {
    if (_db == null) throw Exception('Database not initialized');
    final results = await _db!.rawQuery('SELECT COUNT(*) FROM $table');
    return Sqflite.firstIntValue(results) ?? 0;
  }

  Future<int> update(Map<String, dynamic> row) async {
    if (_db == null) throw Exception('Database not initialized');
    int id = row[columnId];
    return await _db!.update(
      table,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.delete(
      table,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
