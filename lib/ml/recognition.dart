// dart:ui 에서 Rect(사각형 영역) 타입을 가져온다.
// Rect 는 left/top/right/bottom 네 값으로 화면 위의 직사각형을 표현하는 기본 타입이다.
import 'dart:ui';

/// 얼굴 인식 결과 **한 건**을 담는 데이터 모델 클래스.
///
/// 이 클래스는 두 가지 용도로 재사용된다. 처음에는 헷갈리기 쉬우니 구분해서 보자.
///
/// 1. **인식 결과** — 카메라에 잡힌 얼굴을 인식했을 때
///    (`Recognizer.recognize()` 가 만들어서 돌려준다)
///    → `name`=가장 닮은 사람 이름, `location`=화면 속 얼굴 위치, `distance`=닮은 정도
///
/// 2. **DB에서 불러온 등록 얼굴** — 앱 시작 시 저장된 얼굴들을 메모리에 캐시할 때
///    (`Recognizer.loadRegisteredFaces()` 가 만든다)
///    → `location`은 의미가 없어서 `Rect.zero`, `distance`도 의미가 없어서 `0`을 넣는다.
///
/// 필드가 `final`이 아니므로 생성 후에도 값을 바꿀 수 있다.
class Recognition {
  /// 인식된 사람의 이름. 일치하는 등록 얼굴이 없으면 `"Unknown"` 이 들어간다.
  String name;

  /// 카메라 **원본 이미지 좌표계** 기준의 얼굴 사각형 위치.
  ///
  /// 주의: 화면(위젯) 좌표가 아니다. 화면에 사각형을 그릴 때는
  /// `FaceDetectorPainter` 가 이 값에 배율(scaleX/scaleY)을 곱해서 변환한다.
  Rect location;

  /// FaceNet 모델이 뽑아낸 얼굴 특징 벡터. 기본 설정에서는 512개의 실수다.
  ///
  /// "얼굴을 숫자 512개로 요약한 지문"이라고 생각하면 된다.
  /// 같은 사람의 얼굴이면 이 숫자들의 방향이 비슷해진다.
  List<double> embeddings;

  /// 등록된 얼굴과 얼마나 닮았는지를 나타내는 값.
  ///
  /// ⚠️ 이름은 "거리(distance)"지만 실제로 들어가는 값은 **코사인 유사도**다.
  /// 즉 **값이 클수록 더 닮은 것**이다 (-1.0 ~ 1.0, 1.0이 가장 닮음).
  /// 이름과 의미가 반대라 헷갈리기 쉬우니 주의할 것.
  /// (자세한 계산은 `Recognizer.findNearest()` 참고)
  double distance;

  /// 네 값을 순서대로 받아 객체를 만든다.
  /// `this.name` 같은 표기는 "받은 인자를 같은 이름의 필드에 바로 대입"하라는 Dart 문법이다.
  Recognition(this.name, this.location, this.embeddings, this.distance);
}
