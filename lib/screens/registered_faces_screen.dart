// Uint8List: 이미지 바이트를 담는 타입. DB의 BLOB 을 그대로 받는다.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';

/// 등록된 얼굴 목록을 보여주고 삭제할 수 있는 화면.
///
/// 이 프로젝트에서 **완성되어 있는 유일한 화면**이라, 화면 하나가 어떻게
/// 만들어지는지 익히기에 가장 좋은 예제다.
///
/// 목록 데이터(`faces`)가 DB를 읽어온 뒤에 바뀌고, 삭제하면 또 바뀐다.
/// 이렇게 **화면이 그려진 뒤에도 값이 변하는 화면**은 StatefulWidget 으로 만든다.
class RegisteredFacesScreen extends StatefulWidget {
  // 참고: 다른 화면들은 요즘 방식인 `super.key` 를 쓰는데 여기만 옛 방식이다.
  // `const RegisteredFacesScreen({super.key});` 로 바꿔도 동작은 완전히 같다.
  const RegisteredFacesScreen({Key? key}) : super(key: key);

  // StatefulWidget 은 UI를 직접 그리지 않고, 실제 내용을 담당할 State 객체를 만든다.
  @override
  _RegisteredFacesScreenState createState() => _RegisteredFacesScreenState();
}

/// 위 위젯의 실제 알맹이. 화면에 보일 내용과 바뀌는 값(상태)을 여기서 관리한다.
class _RegisteredFacesScreenState extends State<RegisteredFacesScreen> {
  /// 이 화면 전용 DB 접근 객체.
  /// (Recognizer 도 자기 것을 따로 갖고 있다 — 공유하지 않는다)
  final dbHelper = DatabaseHelper();

  /// 화면에 표시할 얼굴 목록. DB에서 읽은 행들이 그대로 들어온다.
  /// 각 항목은 `{'id': 1, 'name': '홍길동', 'embedding': '...', 'image': [바이트]}` 형태다.
  List<Map<String, dynamic>> faces = [];

  /// 화면이 처음 만들어질 때 **딱 한 번** 호출된다.
  /// 초기 데이터를 불러오기 좋은 자리다.
  @override
  void initState() {
    super.initState();
    // initState 는 async 로 만들 수 없어서 await 없이 호출한다.
    // 데이터가 도착하면 아래 loadFaces 안의 setState 가 화면을 다시 그려준다.
    loadFaces();
  }

  /// DB에서 등록된 얼굴을 전부 읽어와 화면에 반영한다.
  Future<void> loadFaces() async {
    // 이 화면의 dbHelper 는 아직 열려 있지 않을 수 있으므로 먼저 init() 한다.
    await dbHelper.init();
    final data = await dbHelper.queryAllRows();

    // setState: "값이 바뀌었으니 화면을 다시 그려라"라고 Flutter에 알리는 함수.
    // 이걸 빼먹으면 faces 값은 바뀌어도 화면은 그대로라 흔한 실수 1순위다.
    setState(() {
      faces = data;
    });
  }

  /// 얼굴 하나를 DB에서 지우고 목록을 새로고침한다.
  Future<void> deleteFace(int id) async {
    await dbHelper.delete(id);
    // 지운 뒤 다시 읽어오면 화면에서도 사라진다.
    loadFaces();
  }

  /// 삭제 전에 "정말 지울까요?" 확인 창을 띄운다.
  ///
  /// 실수로 데이터를 날리는 것을 막기 위한 안전장치다.
  void _confirmDelete(BuildContext context, int id) {
    // showDialog: 화면 위에 떠 있는 작은 창을 띄운다.
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this face?'),
        // actions: 창 아래쪽에 놓일 버튼들.
        actions: [
          TextButton(
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.deepPurple),
            ),
            // Navigator.pop: 지금 떠 있는 창(또는 화면)을 닫는다.
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () {
              // 창을 먼저 닫고 나서 삭제한다.
              Navigator.pop(context);
              deleteFace(id);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 바깥 Container 는 배경 그라데이션을 깔기 위한 것이고,
    // 그 위에 배경이 투명한 Scaffold 를 얹어 그라데이션이 비쳐 보이게 했다.
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // ⚠️ withAlpha 는 0~255 범위를 받는데 400을 넘겼다.
          // 범위를 벗어나 결국 완전 불투명으로 처리되므로, 원래 의도대로
          // 반투명하게 만들려면 withAlpha(150) 처럼 255 이하 값을 써야 한다.
          colors: [Colors.deepPurple.withAlpha(400), Color(0xFFffffff)],
        ),
      ),
      child: Scaffold(
        // 투명으로 둬야 위 Container 의 그라데이션이 보인다.
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Registered Faces',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
          ),
          centerTitle: true,
          backgroundColor: Colors.deepPurple.withAlpha(400),
          elevation: 0,
          // 뒤로가기 버튼과 제목의 색.
          foregroundColor: Colors.white,
        ),
        body: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          // `조건 ? A : B` — 목록이 비었으면 안내 문구를, 아니면 목록을 그린다.
          child: faces.isEmpty
              // ── 등록된 얼굴이 하나도 없을 때 ──
              ? Center(
                  child: Column(
                    // mainAxisSize.min: 세로로 꽉 채우지 말고 내용만큼만 차지하라.
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.face_retouching_off,
                        size: 80,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        "No faces registered yet.",
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ),
                )
              // ── 등록된 얼굴이 있을 때 ──
              // ListView.builder: 화면에 보이는 항목만 그때그때 만들어 그린다.
              // 항목이 수백 개여도 느려지지 않는 스크롤 목록의 기본 방식이다.
              : ListView.builder(
                  itemCount: faces.length,
                  padding: const EdgeInsets.only(bottom: 20),
                  // itemBuilder 는 index 번째 항목의 위젯을 만들어 돌려주는 함수다.
                  // 0, 1, 2... 순서로 필요할 때마다 Flutter가 호출한다.
                  itemBuilder: (context, index) {
                    final face = faces[index];
                    // DB의 BLOB 컬럼이 Uint8List 로 넘어온다.
                    Uint8List? imageBytes = face[DatabaseHelper.columnImage];

                    // 카드 한 장
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(20),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      // Stack: 위젯을 겹쳐 쌓는다.
                      // 카드 내용 위에 삭제 버튼을 띄우기 위해 사용했다.
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // ClipRRect: 자식(이미지)의 모서리를 둥글게 잘라낸다.
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  // 이미지가 없을 수도 있으니 null 검사를 한다.
                                  child: imageBytes != null
                                      // Image.memory: 파일이나 URL이 아니라
                                      // 메모리의 바이트 배열로부터 이미지를 그린다.
                                      ? Image.memory(
                                          imageBytes,
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        )
                                      // 이미지가 없으면 회색 사람 아이콘을 대신 보여준다.
                                      : Container(
                                          width: 80,
                                          height: 80,
                                          color: Colors.grey[300],
                                          child: const Icon(
                                            Icons.person,
                                            size: 40,
                                            color: Colors.grey,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        // `?? ''` — 이름이 null 이면 빈 문자열로.
                                        // Text 에 null 을 넣으면 에러가 나기 때문이다.
                                        face[DatabaseHelper.columnName] ?? '',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        // `${}` 로 변수 값을 문자열 안에 끼워 넣는다.
                                        'ID: ${face[DatabaseHelper.columnId]}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Delete button at top-right corner
                          // Positioned: Stack 안에서 정확한 위치를 지정한다.
                          Positioned(
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: () => _confirmDelete(
                                context,
                                face[DatabaseHelper.columnId],
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.deepPurple,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(1, 2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(6),
                                child: const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// 화면이 완전히 사라질 때 호출된다. 열어둔 자원을 정리하는 자리다.
  ///
  /// 여기서 DB 연결을 닫아준다. 닫지 않으면 연결이 계속 남아 있게 된다.
  @override
  void dispose() {
    dbHelper.close();
    // super.dispose() 는 항상 **마지막에** 호출하는 것이 규칙이다.
    super.dispose();
  }
}
