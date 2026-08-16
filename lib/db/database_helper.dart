// path 패키지: 경로 문자열을 안전하게 이어붙이는 join() 함수를 제공한다.
// (플랫폼별 구분자 차이를 알아서 처리해 준다)
import 'package:path/path.dart';
// sqflite 패키지: 기기 내부에 SQLite 데이터베이스를 만들고 다루는 기능.
import 'package:sqflite/sqflite.dart';
// path_provider 패키지: "앱 문서 폴더는 어디인가?" 같은 플랫폼별 경로를 알려준다.
// 이름이 비슷하지만 위의 path 패키지와는 완전히 다른 패키지다.
import 'package:path_provider/path_provider.dart';

/// 등록된 얼굴 정보를 기기 내부 SQLite DB에 저장/조회/삭제하는 클래스.
///
/// 서버 없이 **기기 안에만** 저장되므로, 앱을 삭제하면 데이터도 함께 사라진다.
///
/// ⚠️ 이 클래스는 싱글턴이 아니다. `Recognizer` 와 `RegisteredFacesScreen` 이
/// 각각 자기 인스턴스를 만들어 쓴다. 그래서 **어떤 메서드를 쓰기 전에도
/// 반드시 `await init()` 을 먼저 호출**해야 한다.
/// (init() 은 여러 번 불러도 안전하게 만들어져 있다)
class DatabaseHelper {
  /// 실제로 생성될 DB 파일 이름.
  /// 앞의 `_` 는 Dart에서 "이 파일 밖에서는 못 쓰는 비공개 멤버"라는 뜻이다.
  static const _databaseName = "MyDatabase.db";

  /// DB 스키마 버전.
  ///
  /// 💡 나중에 컬럼을 추가하는 등 아래 CREATE TABLE 구조를 바꾸려면
  ///    이 숫자를 2, 3... 으로 올리고 openDatabase 에 `onUpgrade:` 를 추가해야 한다.
  ///    그냥 CREATE TABLE 만 고치면 **이미 앱을 설치한 기기에서는 반영되지 않는다.**
  ///    (onCreate 는 DB 파일이 처음 만들어질 때 딱 한 번만 실행되기 때문)
  static const _databaseVersion = 1;

  /// 테이블 이름.
  static const table = 'my_table';

  // 컬럼 이름들을 상수로 빼 두었다.
  // 이렇게 하면 오타로 인한 버그를 막을 수 있고, 이름을 바꿀 때 한 곳만 고치면 된다.
  // 다른 파일에서는 `DatabaseHelper.columnName` 처럼 클래스 이름을 붙여 사용한다.

  /// 자동 증가하는 기본키(PK).
  static const columnId = 'id';

  /// 등록한 사람 이름.
  static const columnName = 'name';

  /// 얼굴 특징 벡터. 실수 배열을 **콤마로 이어붙인 문자열(TEXT)** 로 저장한다.
  /// 예: "0.12,-0.98,0.44,..." (512개)
  static const columnEmbedding = 'embedding';

  /// 등록 당시 잘라낸 얼굴 사진. JPEG 바이트를 BLOB 으로 저장한다.
  static const columnImage = 'image';

  /// 열려 있는 DB 연결. init() 전에는 null 이라서 `?` (nullable) 타입이다.
  Database? _db;

  /// DB 파일을 열고(없으면 새로 만들고) 사용할 준비를 한다.
  ///
  /// 다른 메서드를 쓰기 전에 **반드시 먼저 `await` 로 호출**해야 한다.
  Future<void> init() async {
    // 이미 열려 있으면 아무것도 하지 않고 그냥 끝낸다.
    // 덕분에 여러 번 호출해도 안전하다(재진입 안전).
    if (_db != null && _db!.isOpen) return;

    // 앱 전용 문서 폴더 경로를 얻는다. (iOS/Android가 각각 다른 위치를 준다)
    final documentsDirectory = await getApplicationDocumentsDirectory();

    // 폴더 경로 + 파일 이름 => 최종 DB 파일 경로
    final path = join(documentsDirectory.path, _databaseName);

    // 파일이 없으면 새로 만들면서 onCreate 를 호출하고, 있으면 그냥 연다.
    _db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  /// DB 파일이 **처음 만들어질 때 딱 한 번** 호출되어 테이블을 생성한다.
  ///
  /// `'''...'''` 는 여러 줄 문자열이고, `$table` 처럼 `$` 를 붙이면
  /// 위에서 선언한 상수 값이 문자열 안에 끼워 넣어진다(문자열 보간).
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

  /// 행 하나를 추가하고, 새로 만들어진 행의 id 를 돌려준다.
  ///
  /// [row] 는 `{컬럼이름: 값}` 형태의 Map 이다.
  /// ⚠️ 위 스키마에서 image 가 `NOT NULL` 이므로 이미지 없이 넣으면 실패한다.
  Future<int> insert(Map<String, dynamic> row) async {
    // init() 을 깜빡했을 때 원인을 바로 알 수 있도록 명확한 에러를 던진다.
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.insert(table, row);
  }

  /// 테이블의 모든 행을 읽어온다. (등록된 얼굴 전체 목록)
  Future<List<Map<String, dynamic>>> queryAllRows() async {
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.query(table);
  }

  /// 등록된 얼굴이 몇 개인지 센다.
  ///
  /// 참고: 현재 이 프로젝트에서는 아직 호출하는 곳이 없다.
  /// "등록 인원 3명" 같은 표시를 넣고 싶을 때 쓰면 된다.
  Future<int> queryRowCount() async {
    if (_db == null) throw Exception('Database not initialized');
    final results = await _db!.rawQuery('SELECT COUNT(*) FROM $table');
    // 결과가 비어 있으면 0을 반환한다 (`??` 는 "왼쪽이 null이면 오른쪽" 이라는 뜻).
    return Sqflite.firstIntValue(results) ?? 0;
  }

  /// 기존 행을 수정한다. [row] 안에 반드시 id 가 들어 있어야 한다.
  ///
  /// 참고: 현재 이 프로젝트에서는 아직 호출하는 곳이 없다.
  /// "등록된 이름 바꾸기" 기능을 만들 때 쓰면 된다.
  Future<int> update(Map<String, dynamic> row) async {
    if (_db == null) throw Exception('Database not initialized');
    int id = row[columnId];
    return await _db!.update(
      table,
      row,
      // `?` 자리에 whereArgs 의 값이 들어간다.
      // 이렇게 해야 SQL 인젝션을 막을 수 있으므로 문자열을 직접 이어붙이지 말 것.
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  /// id 에 해당하는 행을 삭제하고, 삭제된 행 수를 돌려준다.
  Future<int> delete(int id) async {
    if (_db == null) throw Exception('Database not initialized');
    return await _db!.delete(table, where: '$columnId = ?', whereArgs: [id]);
  }

  /// DB 연결을 닫는다. 화면이 사라질 때(dispose) 호출해 자원을 정리한다.
  Future<void> close() async {
    // `?.` 는 "_db 가 null이 아닐 때만 close() 호출" 이라는 뜻이다.
    await _db?.close();
    // 다시 null 로 되돌려 두면 나중에 init() 을 부를 때 정상적으로 다시 열린다.
    _db = null;
  }
}
