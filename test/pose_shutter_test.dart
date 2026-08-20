// PoseShutter(머리 자세 자동 촬영 판정기) 단위 테스트.
//
// 이 클래스는 Flutter 위젯이나 카메라에 의존하지 않는 순수 Dart 코드라
// 실기기 없이 검증할 수 있다. 기준 각도를 넘긴 프레임에서 곧바로 찍히는지,
// 같은 방향이 두 번 찍히지 않는지를 여기서 확인한다.
//
// 실행: fvm flutter test test/pose_shutter_test.dart

import 'package:flutter_face_recognition_realtime/pose_shutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoseShutter', () {
    test('좌우 45도를 넘긴 첫 프레임에서 바로 촬영된다', () {
      final PoseShutter shutter = PoseShutter();

      // 기준(45도)에 정확히 닿은 순간부터 대상이다.
      expect(shutter.update(angleY: 45), HeadPoseDirection.right);
      expect(shutter.captured, contains(HeadPoseDirection.right));
    });

    test('위아래 30도를 넘긴 첫 프레임에서 바로 촬영된다', () {
      final PoseShutter shutter = PoseShutter();

      expect(shutter.update(angleX: 30), HeadPoseDirection.up);
      expect(shutter.captured, contains(HeadPoseDirection.up));
    });

    test('자세를 유지하지 않아도 된다 (한 프레임이면 충분하다)', () {
      final PoseShutter shutter = PoseShutter();

      // 정면 → 좌 → 정면 처럼 스쳐 지나가도 그 한 프레임에서 찍힌다.
      expect(shutter.update(angleY: 0), isNull);
      expect(shutter.update(angleY: -50), HeadPoseDirection.left);
      expect(shutter.update(angleY: 0), isNull);
    });

    test('기준에 못 미치는 각도로는 촬영되지 않는다', () {
      final PoseShutter shutter = PoseShutter();

      for (int i = 0; i < 10; i++) {
        // 좌우는 45도, 위아래는 30도가 기준이다.
        expect(shutter.update(angleY: 44.9, angleX: 29.9), isNull);
      }
      expect(shutter.captured, isEmpty);
    });

    test('같은 방향은 한 번만 찍힌다', () {
      final PoseShutter shutter = PoseShutter();

      expect(shutter.update(angleY: 50), HeadPoseDirection.right);
      // 고개를 계속 돌리고 있어도 두 번째부터는 신호가 없다.
      for (int i = 0; i < 20; i++) {
        expect(shutter.update(angleY: 50), isNull);
      }
      expect(shutter.captured.length, 1);
    });

    test('부호에 따라 좌/우, 위/아래가 갈린다', () {
      final PoseShutter shutter = PoseShutter();

      expect(shutter.update(angleY: -50), HeadPoseDirection.left);
      expect(shutter.update(angleY: 50), HeadPoseDirection.right);
      expect(shutter.update(angleX: 40), HeadPoseDirection.up);
      expect(shutter.update(angleX: -40), HeadPoseDirection.down);
    });

    test('대각선이면 기준을 더 크게 초과한 축만 찍는다', () {
      final PoseShutter shutter = PoseShutter();

      // 좌우는 기준의 1.0배(45/45), 위아래는 1.5배(45/30) 초과.
      // 따라서 위아래(up)가 선택되어야 한다.
      expect(shutter.update(angleY: 45, angleX: 45), HeadPoseDirection.up);
      expect(shutter.captured, <HeadPoseDirection>{HeadPoseDirection.up});
    });

    test('네 방향을 다 찍으면 완료 상태가 되고 더는 신호를 내지 않는다', () {
      final PoseShutter shutter = PoseShutter();

      shutter.update(angleY: -50);
      shutter.update(angleY: 50);
      shutter.update(angleX: 40);
      shutter.update(angleX: -40);

      expect(shutter.isComplete, isTrue);
      // 완료 후에는 어떤 각도를 넣어도 null 이다.
      expect(shutter.update(angleY: 50), isNull);
    });

    test('reset 하면 처음부터 다시 찍을 수 있다', () {
      final PoseShutter shutter = PoseShutter();

      shutter.update(angleY: 50);
      shutter.reset();

      expect(shutter.captured, isEmpty);
      expect(shutter.isComplete, isFalse);
      expect(shutter.update(angleY: 50), HeadPoseDirection.right);
    });

    test('undo 하면 저장 실패한 방향을 다시 찍을 수 있다', () {
      final PoseShutter shutter = PoseShutter();

      expect(shutter.update(angleY: 50), HeadPoseDirection.right);
      shutter.undo(HeadPoseDirection.right);

      expect(shutter.captured, isEmpty);
      expect(shutter.update(angleY: 50), HeadPoseDirection.right);
    });

    test('각도가 null 이면(ML Kit 이 계산하지 못하면) 무시된다', () {
      final PoseShutter shutter = PoseShutter();

      for (int i = 0; i < 10; i++) {
        expect(shutter.update(angleX: null, angleY: null), isNull);
      }
      expect(shutter.captured, isEmpty);
    });
  });
}
