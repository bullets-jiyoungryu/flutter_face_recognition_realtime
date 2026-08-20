/// **머리 자세로 셔터를 누르는 판정기.**
///
/// 인식 화면(`screens/recognition_screen.dart`)이 매 프레임 각도를 넘겨주면,
/// "지금 촬영해야 하는가"를 판단해 방향을 돌려준다.
/// 실제 촬영·저장은 화면 쪽이 맡는다. 이 파일에는 **판정 규칙만** 있다.
///
/// Flutter 에 의존하지 않는 순수 Dart 클래스라, 화면 없이도 단위 테스트를 쓸 수 있다.
library;

/// 촬영 대상이 되는 네 방향.
///
/// ML Kit 이 주는 각도의 부호를 그대로 따른다.
/// - [right] / [left] : `headEulerAngleY` (yaw) 가 양수 / 음수
/// - [up] / [down]    : `headEulerAngleX` (pitch) 가 양수 / 음수
///
/// ⚠️ 여기서 말하는 좌우는 사람 기준이 아니라 **ML Kit 이 처리한 이미지 기준**이다.
///    전면 카메라는 프리뷰만 거울처럼 반전되어 보이므로, 실기기에서 봤을 때
///    좌우가 반대로 느껴진다면 이 enum 의 라벨만 서로 바꾸면 된다.
enum HeadPoseDirection { left, right, up, down }

/// enum 에 사람이 읽을 이름과 파일명 조각을 붙여주는 확장(extension).
///
/// `extension` 은 남이 만든 타입(여기서는 내가 만든 enum)에
/// 나중에 기능을 덧붙이는 Dart 문법이다.
extension HeadPoseDirectionLabel on HeadPoseDirection {
  /// 화면에 표시할 이름. 예: `← 좌 45°`
  String get label {
    switch (this) {
      case HeadPoseDirection.left:
        return '← 좌 45°';
      case HeadPoseDirection.right:
        return '우 45° →';
      case HeadPoseDirection.up:
        return '↑ 위 30°';
      case HeadPoseDirection.down:
        return '↓ 아래 30°';
    }
  }

  /// 저장 파일명에 넣을 짧은 영문 조각. 한글은 파일명에서 깨질 수 있어 따로 둔다.
  String get fileTag {
    switch (this) {
      case HeadPoseDirection.left:
        return 'left45';
      case HeadPoseDirection.right:
        return 'right45';
      case HeadPoseDirection.up:
        return 'up30';
      case HeadPoseDirection.down:
        return 'down30';
    }
  }
}

/// 머리 자세가 목표 각도에 도달했는지 보고 **방향마다 한 장씩** 촬영 신호를 낸다.
///
/// 판정 규칙은 두 줄로 끝난다.
///
/// 1. **즉시 촬영** — 좌우(yaw)가 [yawThreshold] 이상, 위아래(pitch)가
///    [pitchThreshold] 이상이 된 **바로 그 프레임**에 촬영 신호를 낸다.
///    자세를 얼마간 유지할 필요가 없다.
/// 2. **방향당 1회** — 이미 찍은 방향은 [reset] 전까지 다시 찍지 않는다.
///    이 규칙이 없으면 고개를 돌리고 있는 동안 매 프레임 셔터가 터진다.
///
/// 네 방향을 모두 찍으면 [isComplete] 가 true 가 되고, 그 뒤로는 아무 신호도 내지 않는다.
/// 다시 찍으려면 화면의 초기화 버튼이 [reset] 을 호출한다.
///
/// ⚠️ 각도는 프레임마다 몇 도씩 떨린다. 즉시 촬영이므로 기준선을 스치듯
///    지나가는 순간에도 한 장이 찍힌다. 그 대신 반응이 가장 빠르다.
///    "잠깐 스친 각도는 무시"가 필요해지면 여기에 연속 프레임 카운트를 다시 넣으면 된다.
class PoseShutter {
  /// 좌우(yaw) 목표 각도. 이 값 이상으로 고개를 돌리면 촬영 대상이다.
  static const double yawThreshold = 45;

  /// 위아래(pitch) 목표 각도.
  static const double pitchThreshold = 30;

  /// **이미 촬영을 마친 방향들.** 화면이 진행 상황을 그릴 때도 읽어 간다.
  final Set<HeadPoseDirection> captured = <HeadPoseDirection>{};

  /// 네 방향을 모두 찍었는가.
  bool get isComplete => captured.length == HeadPoseDirection.values.length;

  /// 이번 프레임의 각도를 넣고 **촬영할 방향**을 돌려받는다.
  ///
  /// 촬영할 것이 없으면 null 이다. 각도가 null(= ML Kit 이 계산하지 못함)이면
  /// 그 축은 판정에서 빠진다.
  ///
  /// [angleX] 는 pitch(위아래), [angleY] 는 yaw(좌우)다.
  HeadPoseDirection? update({double? angleX, double? angleY}) {
    // 이미 네 방향을 다 찍었으면 더 볼 것이 없다.
    if (isComplete) return null;

    // ① 이번 프레임이 어느 방향에 해당하는지 하나만 고른다.
    //
    //    좌우와 위아래가 동시에 기준을 넘는 경우(대각선으로 돌린 경우)가 있는데,
    //    한 프레임에 두 장을 찍으면 둘 다 어중간한 사진이 된다.
    //    그래서 "기준을 몇 배 초과했는지"를 비교해 더 확실한 쪽만 고른다.
    HeadPoseDirection? candidate;
    double bestRatio = 1.0;

    if (angleY != null && angleY.abs() >= yawThreshold) {
      candidate = angleY > 0 ? HeadPoseDirection.right : HeadPoseDirection.left;
      bestRatio = angleY.abs() / yawThreshold;
    }
    if (angleX != null && angleX.abs() >= pitchThreshold) {
      final double ratio = angleX.abs() / pitchThreshold;
      if (candidate == null || ratio > bestRatio) {
        candidate = angleX > 0 ? HeadPoseDirection.up : HeadPoseDirection.down;
      }
    }

    // ② 조건을 만족하는 방향이 없으면 여기서 끝.
    if (candidate == null) return null;

    // ③ 이미 찍은 방향이면 다시 찍지 않는다.
    if (captured.contains(candidate)) return null;

    // ④ 기준을 넘은 바로 이 프레임에서 촬영 신호를 낸다.
    captured.add(candidate);
    return candidate;
  }

  /// 촬영은 결정됐지만 **저장에 실패**했을 때 되돌린다.
  ///
  /// 이 처리가 없으면 권한 거부나 디스크 오류로 한 번 실패한 방향을
  /// 영영 다시 찍을 수 없게 된다.
  void undo(HeadPoseDirection direction) {
    captured.remove(direction);
  }

  /// 처음 상태로 되돌린다. 화면의 초기화 버튼이 호출한다.
  void reset() {
    captured.clear();
  }
}
