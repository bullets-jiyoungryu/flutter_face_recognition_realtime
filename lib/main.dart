// camera 패키지: 기기의 카메라 목록 조회 및 카메라 제어 기능을 제공한다.
import 'package:camera/camera.dart';

// material 패키지: Flutter의 기본 UI 위젯 모음 (MaterialApp, Scaffold, Text 등).
import 'package:flutter/material.dart';

// 앱의 첫 화면. 같은 프로젝트 안의 파일은 이렇게 상대 경로로 가져온다.
import 'screens/home_screen.dart';

/// 이 기기에서 사용할 수 있는 카메라 목록 (예: [0]=후면, [1]=전면).
///
/// 파일 맨 바깥(최상위)에 선언했기 때문에 `import '../main.dart';` 한 줄이면
/// 앱 어디서든 `cameras` 라는 이름으로 접근할 수 있는 **전역 변수**가 된다.
/// 이 프로젝트에서 Provider/Riverpod 같은 상태관리 없이 카메라 목록을
/// 공유하는 유일한 통로다.
///
/// `late` 는 "지금은 값이 없지만 처음 사용하기 전에 반드시 채워 넣겠다"는 약속이다.
/// 아래 main() 에서 값을 넣기 전에 접근하면 LateInitializationError 가 발생한다.
late List<CameraDescription> cameras;

/// 앱의 진입점. 앱을 실행하면 가장 먼저 이 함수가 호출된다.
///
/// `async` 이므로 반환 타입이 `Future<void>` 다.
/// runApp() 전에 카메라 목록을 미리 받아와야 해서 비동기로 만들었다.
Future<void> main() async {
  // runApp() 보다 먼저 네이티브 기능(카메라 등)을 쓰려면 이 줄이 반드시 필요하다.
  // Flutter 엔진과 Dart 코드를 연결하는 통로를 미리 준비시키는 역할이다.
  // 이 줄이 없으면 availableCameras() 호출 시 에러가 난다.
  WidgetsFlutterBinding.ensureInitialized();

  // 기기에 달린 카메라 목록을 조회해 전역 변수에 저장한다.
  // 목록의 각 항목(CameraDescription)에는 전면/후면 구분(lensDirection)과
  // 센서가 몇 도 돌아가 붙어 있는지(sensorOrientation)가 들어 있다.
  // 화면들의 getInputImage() 가 이 sensorOrientation 으로 회전을 보정한다.
  //
  // ⚠️ 카메라가 없는 시뮬레이터/에뮬레이터에서는 빈 목록이 반환된다.
  //    각 화면이 cameras[1] (전면)을 직접 사용하므로 실기기에서 실행해야 한다.
  // ⚠️ [0]=후면, [1]=전면 순서는 **보장된 규칙이 아니다.** 대부분의 기기가
  //    그렇게 주는 것에 기대고 있을 뿐이다. 안전하게 하려면 인덱스 대신
  //    `cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front)`
  //    처럼 방향으로 찾는 것이 좋다.
  cameras = await availableCameras();

  // 위젯 트리를 화면에 띄운다. 여기서부터 Flutter 앱이 시작된다.
  runApp(const MyApp());
}

/// 앱 전체를 감싸는 최상위 위젯.
///
/// 화면이 바뀌어도 이 위젯 자체는 다시 그려질 일이 없으므로
/// (내부에 변하는 상태가 없으므로) StatefulWidget 이 아닌 **StatelessWidget** 이다.
class MyApp extends StatelessWidget {
  // 생성자. `super.key` 는 부모(StatelessWidget)의 key 파라미터로 그대로 넘긴다는 뜻이다.
  // key 는 Flutter가 위젯을 구분할 때 쓰는 식별자로, 관례상 항상 받아두는 것이 좋다.
  const MyApp({super.key});

  /// 이 위젯이 어떤 화면을 그릴지 정의한다. Flutter가 필요할 때 자동으로 호출한다.
  @override
  Widget build(BuildContext context) {
    // MaterialApp: 화면 전환(Navigator), 테마, 폰트 등 앱의 기본 뼈대를 제공한다.
    // home: 에 지정한 위젯이 앱을 켰을 때 보이는 첫 화면이 된다.
    //
    // 💡 화면을 더 추가하고 이름으로 이동하고 싶다면 여기에 routes: 를 추가하면 된다.
    //    예) routes: {'/register': (_) => const RegistrationScreen()}
    // 💡 앱 전체 색상/폰트를 바꾸려면 theme: ThemeData(...) 를 추가한다.
    return const MaterialApp(home: HomeScreen());
  }
}
