# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

온디바이스 실시간 얼굴 인식 Flutter 앱 (Android / iOS). 네트워크 호출 없이 기기 내부에서만 동작한다.

파이프라인: **카메라 스트림 → ML Kit 얼굴 검출 → 얼굴 크롭 → TFLite FaceNet 임베딩(512차원) → SQLite에 저장된 임베딩과 코사인 유사도 비교**

> **중요**: 파이프라인은 아직 **완성되지 않았다**. `lib/screens/registration_screen.dart`와 `lib/screens/recognition_screen.dart`의 검출·인식 로직은 `//TODO` 주석과 주석 처리된 코드로만 남아 있다. 현재 두 화면은 카메라 프리뷰와 전/후면 전환만 실제로 동작한다. 반면 `lib/ml/recognizer.dart`와 `lib/db/database_helper.dart`는 완전히 구현되어 있으므로, 화면 쪽 TODO를 채우는 것이 남은 작업이다.

## 개발 명령어

Flutter 버전이 `.fvmrc`로 **3.44.4**에 고정되어 있다. 항상 `fvm` 프리픽스를 사용한다.

```bash
fvm flutter pub get                 # 의존성 설치
fvm flutter analyze                 # 정적 분석 (린트)
fvm flutter test                    # 전체 테스트
fvm flutter test test/widget_test.dart --plain-name '테스트 이름'   # 단일 테스트
fvm flutter run                     # 디버그 실행 (실기기 필요)
fvm flutter build apk --release
fvm flutter build ios --release
```

`fvm flutter run`은 **실기기에서만 의미가 있다**. `main()`이 `availableCameras()`를 호출하고 각 화면이 `cameras[1]`(전면)을 직접 인덱싱하므로 카메라가 없는 시뮬레이터/에뮬레이터에서는 시작 즉시 실패한다.

## 아키텍처

```
lib/
├── main.dart                 전역 `cameras` 리스트 초기화 + MaterialApp(home: HomeScreen)
├── util.dart                 CameraImage → img.Image 픽셀 포맷 변환
├── ml/
│   ├── recognition.dart      Recognition: name / location(Rect) / embeddings / distance
│   └── recognizer.dart       TFLite 인터프리터 + 등록 얼굴 캐시 + 최근접 탐색
├── db/
│   └── database_helper.dart  sqflite CRUD (MyDatabase.db, 테이블 my_table)
└── screens/
    ├── home_screen.dart              3개 진입점 카드
    ├── registration_screen.dart      얼굴 등록 (미완성)
    ├── recognition_screen.dart       실시간 인식 (미완성)
    └── registered_faces_screen.dart  등록 목록 조회/삭제 (완성)
```

### 전역 상태

`main.dart`의 최상위 `late List<CameraDescription> cameras`가 유일한 전역 상태다. 상태관리 라이브러리는 없고 모두 `StatefulWidget` + `setState`다. 화면들은 `import '../main.dart'`로 이 리스트를 가져온다.

### 카메라 프레임 처리 규약

플랫폼별로 프레임 포맷이 갈리며, 이 구분이 코드 전반에 반복된다:

| | Android | iOS |
|---|---|---|
| `ImageFormatGroup` | `nv21` | `bgra8888` |
| `Util` 변환 함수 | `convertNV21()` | `convertBGRA8888ToImage()` |
| 회전 보정 | 기기 방향 + 센서 방향 조합 | 센서 방향 그대로 |

- `startImageStream` 콜백은 `isBusy` 플래그로 프레임을 드롭한다. 새 처리 로직을 넣을 때 `isBusy = false` 복구를 빠뜨리면 스트림이 영구히 멈춘다.
- `getInputImage()`는 `frame!.planes.length != 1`이면 `null`을 반환한다. 즉 단일 plane 포맷(NV21/BGRA8888)만 지원하며, `ImageFormatGroup`을 `yuv420`으로 바꾸면 조용히 동작을 멈춘다.
- 크롭 전에 `img.copyRotate(image, angle: 전면 ? 270 : 90)`으로 세로 방향을 맞춘다 (주석 처리된 `performFaceRecognition` 참고).

### 인식 모델 (`ml/recognizer.dart`)

- 모델: `assets/facenet.tflite`, 입력 `[1, 160, 160, 3]`, 출력 `[1, 512]`. `WIDTH` / `HEIGHT` / `OUTPUT` 상수와 asset 경로는 **함께** 바꿔야 한다.
- `assets/mobile_face_net.tflite`도 번들되어 있으나 현재 코드에서는 사용하지 않는다. 이 모델로 교체하려면 입력 크기와 출력 차원이 다르므로 위 상수를 모두 조정해야 한다.
- 정규화: `(pixel - 127.5) / 127.5`.
- `findNearest()`가 반환하는 `Pair.distance`는 이름과 달리 **코사인 유사도**다. 값이 **클수록** 유사하며, 등록 얼굴이 없으면 `("Unknown", -1)`이 나온다. 임계값 로직은 아직 없다 — 항상 가장 가까운 후보를 그대로 돌려준다.
- 생성자가 `loadModel()`과 `initDB()`를 **await 없이** 호출한다. 생성 직후 `recognize()`를 부르면 `late interpreter`가 아직 초기화되지 않아 `LateInitializationError`가 난다. 화면에서 인식 로직을 붙일 때 준비 완료 시점을 별도로 다뤄야 한다.
- `registered` 맵은 **이름(name)이 키**다. 동일 이름으로 등록하면 DB에는 행이 추가되지만 메모리 캐시는 `putIfAbsent`라 최초 항목만 남는다.

### 데이터 저장 (`db/database_helper.dart`)

- `getApplicationDocumentsDirectory()` 아래 `MyDatabase.db`, 테이블 `my_table`.
- 컬럼: `id` / `name` / `embedding` / `image`.
- **임베딩은 콤마로 join한 TEXT 문자열**로 저장하고 (`embedding.join(",")`), 읽을 때 `split(',')` 후 `double.parse` 한다.
- `image`는 BLOB. `Recognizer.compressImage()`가 폭 300px로 리사이즈한 뒤 품질을 85부터 5씩 낮춰가며 500KB 이하 JPEG로 만든다.
- `DatabaseHelper`는 싱글턴이 아니다. `Recognizer`와 `RegisteredFacesScreen`이 각자 인스턴스를 만들며, 각 인스턴스는 사용 전 `init()`을 호출해야 한다 (`init()`은 재진입에 안전하다). `RegisteredFacesScreen.dispose()`가 자기 인스턴스의 DB를 닫는다.
- `_onCreate`에서 `image BLOB NOT NULL`이므로, 이미지 없이 등록하는 (주석 처리된) 구버전 `registerFaceInDB`를 되살리면 insert가 실패한다.

## 플랫폼 설정에서 주의할 점

- iOS 권한 설명 문자열은 `ios/Runner/Info.plist`에 `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`으로 설정되어 있다 (영문). 두 화면 모두 `enableAudio: false`라 마이크는 실제로 쓰지 않지만, `camera_avfoundation`이 오디오 캡처 API를 링크하므로 심사 대비로 함께 넣어 두었다.
- **iOS 최소 지원 버전은 15.5**다. `google_mlkit_face_detection` / `google_mlkit_commons`의 podspec이 요구하는 값이며, 이보다 낮추면 `pod install`이 실패한다. 이 값은 세 군데가 **함께** 맞아야 한다: `project.pbxproj`의 `IPHONEOS_DEPLOYMENT_TARGET`(Debug/Profile/Release 3개), `ios/Podfile`의 `platform :ios`, 그리고 `flutter` 툴이 생성하는 `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`(자동 생성이므로 직접 수정하지 말 것).
- iOS 플러그인은 CocoaPods과 Swift Package Manager로 나뉘어 들어간다. `google_mlkit_commons` / `google_mlkit_face_detection` / `tflite_flutter`만 SPM 미지원이라 Podfile.lock에 잡히고, `camera_avfoundation` / `sqflite_darwin` / `path_provider_foundation`은 SPM 경로로 처리된다. 따라서 Podfile.lock에 카메라 pod이 없는 것은 정상이다.
- iOS 빌드 설정만 갱신하려면 `fvm flutter build ios --config-only --no-codesign` (`pod install`까지 수행).
- Android 카메라 권한은 `camera_android_camerax` 플러그인 매니페스트에서 머지되므로 앱 매니페스트에 따로 선언하지 않는다.
- Android: AGP 9.0.1 / Kotlin 2.3.20 / Gradle 9.1.0, Java 17 타깃. `applicationId`와 `namespace`는 `kr.co.bullets.flutter_face_recognition_realtime`.
- `android/local.properties`의 `flutter.sdk`는 FVM SDK 경로를 가리켜야 한다.

## 테스트

`test/widget_test.dart`는 **Flutter 템플릿 기본 테스트가 그대로 남아 있어 현재 실패한다** (존재하지 않는 카운터 위젯을 검증). 앱에 맞게 다시 작성하거나 삭제해야 한다. `fvm flutter test`가 실패하는 것을 회귀로 오해하지 말 것.

## 코드 스타일

`analysis_options.yaml`은 `package:flutter_lints/flutter.yaml`을 그대로 include하며 커스텀 룰은 없다. 기존 코드에는 `avoid_print`, `constant_identifier_names`(`WIDTH`/`HEIGHT`/`OUTPUT`), `curly_braces_in_flow_control_structures` 위반이 남아 있다. 새 코드는 린트를 통과시키되, 무관한 기존 위반까지 일괄 수정하지는 말 것.
