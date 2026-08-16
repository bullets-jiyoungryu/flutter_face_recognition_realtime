// Float32List(32비트 실수 고정 길이 배열)를 쓰기 위해 필요하다.
// TFLite 모델은 실수 배열을 입력으로 받으므로 일반 List<double> 대신
// 메모리 배치가 고정된 Float32List 를 쓰는 편이 효율적이다.
import 'dart:typed_data';

// tflite_flutter 패키지: TensorFlow Lite 모델을 기기 안에서 직접 실행한다.
// 네트워크 호출 없이 온디바이스로 추론하기 위한 핵심 패키지다.
import 'package:tflite_flutter/tflite_flutter.dart';

// image 패키지: 순수 Dart 로 이미지 픽셀을 다룬다.
// `as img` 는 "이 패키지의 것들은 img. 을 붙여 쓰겠다"는 별칭이다.
// (Flutter 기본 Image 위젯과 이름이 겹치는 것을 피하기 위함)
import 'package:image/image.dart' as img;

// debugPrint: print 와 비슷하지만 로그가 너무 길 때 잘라서 출력해
// 안드로이드 로그가 통째로 유실되는 것을 막아준다. 릴리즈 빌드에서도 동작한다.
import 'package:flutter/foundation.dart';

/// **라이브니스(생체) 검사기** — 카메라에 잡힌 얼굴이
/// "진짜 사람 얼굴"인지 "사진/화면으로 보여준 가짜 얼굴"인지 판별한다.
///
/// 왜 필요한가?
/// 얼굴 인식(`Recognizer`)만 있으면 등록된 사람의 **사진**을 카메라에 들이대도
/// 그대로 통과된다. 이 클래스는 그런 사진 스푸핑(spoofing)을 걸러내는 역할이다.
///
/// 동작 방식은 `Recognizer` 와 매우 비슷하다.
/// 1. TFLite 모델(`assets/model.tflite`)을 메모리에 올린다.
/// 2. 224x224 얼굴 이미지를 넣는다.
/// 3. 모델이 뱉은 점수 하나로 진짜/가짜를 판단한다.
///
/// ⚠️ **초심자가 걸려 넘어지는 지점**
/// 생성자가 `loadModel()` 을 `await` 없이 호출한다. 즉
/// `LivenessDetector()` 로 만든 직후에는 모델이 아직 로딩 중일 수 있고,
/// 곧바로 [isLive] 를 부르면 `late final _interpreter` 가 아직 대입되지 않아
/// `LateInitializationError` 가 발생한다.
/// 실제로는 카메라 첫 프레임이 오기까지 시간이 걸려서 대부분 문제가 없지만,
/// 이는 "운 좋게 동작하는" 것이지 보장된 동작이 아니다.
/// (같은 문제를 `Recognizer` 도 갖고 있다)
class LivenessDetector {
  /// TFLite 모델을 실행하는 객체.
  ///
  /// `late` 는 "지금은 값이 없지만 쓰기 전에 반드시 채워질 것"이라는 선언이고,
  /// `final` 이라 **한 번만** 대입할 수 있다.
  /// 따라서 [loadModel] 을 두 번 호출하면 두 번째 대입에서 에러가 난다.
  late final Interpreter _interpreter;

  /// 가짜(스푸핑)로 판정할 기준 점수.
  ///
  /// 모델이 내놓은 점수가 이 값보다 **작으면 진짜 얼굴**로 본다.
  /// 기본값 0.5 는 흔히 쓰는 중간값일 뿐이며,
  /// 실제 조명·카메라 환경에서 직접 실험해 조정해야 하는 값이다.
  /// - 값을 낮추면: 판정이 깐깐해져 진짜 얼굴도 가짜로 튕겨낼 수 있다(오검출↑).
  /// - 값을 높이면: 관대해져 사진이 통과할 수 있다(미검출↑).
  final double spoofThreshold;

  /// 생성자. [spoofThreshold] 를 지정하지 않으면 0.5 를 쓴다.
  ///
  /// `this.spoofThreshold = 0.5` 는 "받은 인자를 같은 이름의 필드에 바로 대입하고,
  /// 안 넘어오면 0.5 를 쓴다"는 Dart 문법이다.
  /// 중괄호 `{}` 로 감싸져 있으므로 **이름 있는 선택 인자**다.
  /// 예: `LivenessDetector(spoofThreshold: 0.3)`
  LivenessDetector({this.spoofThreshold = 0.5}) {
    // ⚠️ await 를 붙일 수 없다. Dart 생성자는 async 가 될 수 없기 때문이다.
    // 그래서 모델 로딩은 "백그라운드에서 시작만" 되고 생성자는 즉시 끝난다.
    loadModel('assets/model.tflite');
  }

  /// Load the TFLite model.
  ///
  /// assets 폴더의 모델 파일을 읽어 인터프리터를 만든다.
  /// [assetPath] 는 pubspec.yaml 의 `assets:` 에 포함된 경로여야 한다.
  /// (이 프로젝트는 `assets/` 폴더 전체를 등록해 두었다)
  ///
  /// ⚠️ `Recognizer.loadModel()` 과 달리 try/catch 가 없다.
  /// 파일이 없거나 손상되면 여기서 예외가 그대로 던져지는데,
  /// 생성자에서 await 없이 불렀기 때문에 이 예외를 아무도 받지 않아
  /// "처리되지 않은 비동기 예외"로 로그에만 남는다.
  Future<void> loadModel(String assetPath) async {
    _interpreter = await Interpreter.fromAsset(assetPath);
  }

  /// Close the interpreter when done.
  ///
  /// 모델을 메모리에서 내린다. 화면의 `dispose()` 에서 호출해
  /// 네이티브 메모리를 반납해야 한다. 안 부르면 누수가 된다.
  void close() {
    _interpreter.close();
  }

  /// Run liveness detection on the given image.
  /// Expects a 224x224 RGB image.
  ///
  /// [faceImage] 는 **반드시 224x224 로 리사이즈된 얼굴 이미지**여야 한다.
  /// 크기 검사를 하지 않으므로, 다른 크기를 넣으면 아래 배열 채우기에서
  /// 범위를 벗어나(RangeError) 터지거나 배열이 덜 채워진 채 엉뚱한 결과가 나온다.
  /// 호출하는 쪽(`recognition_screen.dart`)에서
  /// `img.copyResize(croppedFace, width: 224, height: 224)` 로 맞춰서 넘긴다.
  ///
  /// 반환값: 진짜 얼굴이면 `true`, 사진 등 가짜로 판단되면 `false`.
  ///
  /// 참고: 내부에 실제 `await` 가 없어 동기적으로 계산되지만,
  /// 시그니처가 `Future<bool>` 이라 호출부에서는 `await` 를 붙여 쓴다.
  /// (나중에 무거운 연산을 별도 isolate 로 옮길 여지를 남긴 형태로 볼 수 있다)
  Future<bool> isLive(img.Image faceImage) async {
    // 모델 입력용 버퍼. 224(가로) x 224(세로) x 3(RGB) = 150,528개의 실수.
    final input = Float32List(224 * 224 * 3);

    // 버퍼에 값을 채워 넣을 위치를 가리키는 커서.
    int i = 0;

    // img.Image 를 for-in 으로 돌면 왼쪽 위부터 오른쪽 아래로
    // **픽셀이 하나씩** 나온다. 각 픽셀 p 에서 r/g/b 값을 꺼낸다.
    for (final p in faceImage) {
      // 정규화: 0~255 범위의 색상 값을 0.0~1.0 으로 바꾼다.
      //
      // ⚠️ `Recognizer.imageToArray()` 의 정규화 방식과 **다르다**.
      //    - FaceNet(recognizer): (x - 127.5) / 127.5  → -1.0 ~ 1.0
      //    - 이 모델(liveness) : x / 255.0            →  0.0 ~ 1.0
      //    정규화 방식은 모델을 학습시킬 때 쓴 방식과 똑같아야 한다.
      //    임의로 바꾸면 모델은 에러 없이 조용히 엉뚱한 점수를 낸다.
      //
      // `i++` 는 "지금 값을 쓰고 나서 i 를 1 증가"라는 뜻이라
      // R, G, B 가 순서대로 한 칸씩 채워진다.
      input[i++] = p.r / 255.0;
      input[i++] = p.g / 255.0;
      input[i++] = p.b / 255.0;
    }

    // 1차원으로 채운 배열을 모델이 요구하는 4차원 모양으로 재구성한다.
    // [1, 224, 224, 3] = [한 번에 처리할 장수, 세로, 가로, 색상채널]
    // 맨 앞의 1 은 배치 크기(batch size)로, "얼굴 한 장만 넣는다"는 뜻이다.
    final inputTensor = input.reshape([1, 224, 224, 3]);

    // 결과를 받을 빈 배열을 미리 만든다. TFLite 는 값을 반환하는 대신
    // 이렇게 넘겨준 배열을 **채워주는** 방식으로 동작한다.
    // [1, 1] = 얼굴 1장에 대해 점수 1개.
    final outputTensor = Float32List(1).reshape([1, 1]);

    // 추론 실행. 이 한 줄에서 모델이 실제로 계산을 수행한다.
    // 여기서 `_interpreter` 가 아직 준비되지 않았다면
    // LateInitializationError 가 난다(위 클래스 설명 참고).
    _interpreter.run(inputTensor, outputTensor);

    // 결과 꺼내기: [1, 1] 모양이므로 [0][0] 이 유일한 점수다.
    final score = outputTensor[0][0];

    // 개발 중 임계값을 정하려면 이 로그를 보고
    // 진짜 얼굴/사진일 때의 점수 분포를 확인하면 된다.
    debugPrint('Spoof score → $score');

    // 이 모델의 점수는 "가짜일 가능성(spoof score)"이다.
    // 따라서 **작을수록 진짜**이고, 기준값보다 작으면 true(살아있는 얼굴)를 돌려준다.
    // 부등호 방향을 헷갈리기 쉬우니 주의할 것.
    return score < spoofThreshold;
  }
}
