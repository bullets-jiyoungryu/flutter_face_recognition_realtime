// Uint8List: 0~255 사이의 값만 담는 바이트 배열.
// 카메라 프레임의 원본 데이터가 이 타입으로 들어온다.
import 'dart:typed_data';

// camera 패키지: 카메라 프레임을 뜻하는 CameraImage 타입을 쓰기 위해 필요하다.
import 'package:camera/camera.dart';

// image 패키지: 픽셀 단위로 이미지를 다루는 img.Image 타입.
// `as img` 는 Flutter 기본 Image 위젯과 이름이 겹치는 것을 피하기 위한 별칭이다.
import 'package:image/image.dart' as img;

/// 카메라가 준 원본 프레임(`CameraImage`)을 이미지 처리용(`img.Image`)으로
/// 바꿔주는 변환 함수 모음.
///
/// **왜 변환이 필요한가?**
/// 카메라는 성능을 위해 사람이 보는 RGB가 아니라 압축적인 포맷으로 프레임을 준다.
/// - Android: NV21 (YUV 계열 — 밝기 Y + 색상 U/V 를 따로 저장)
/// - iOS: BGRA8888 (픽셀당 파랑/초록/빨강/투명도 4바이트)
///
/// 반면 얼굴을 잘라내고(crop) 크기를 바꾸려면 image 패키지의 `img.Image` 가
/// 필요하다. 그 사이를 이어주는 것이 이 클래스다.
///
/// **YUV가 무엇인지 한 문단 요약**
/// RGB가 "빨강·초록·파랑을 얼마씩 섞을까"라면, YUV는 "얼마나 밝은가(Y) +
/// 어떤 색인가(U, V)"로 나눠 저장하는 방식이다. 사람 눈은 밝기 변화에는
/// 민감하지만 색 변화에는 둔하다. 그래서 밝기는 픽셀마다 저장하고 색은
/// 가로·세로 2픽셀씩 묶어 하나만 저장해도 티가 잘 안 난다.
/// 이 덕분에 데이터가 절반으로 줄어 카메라가 이 포맷을 선호한다.
/// 아래 `convertNV21()` 의 복잡한 인덱스 계산은 전부 이 "색은 2픽셀당 하나"
/// 구조에서 나온다.
///
/// 대부분 `static` 이라 객체를 만들지 않고 `Util.convertNV21(frame)` 처럼 바로 쓴다.
/// (아래쪽 `convertYUV420ToImage` 와 `yuv2rgb` 만 static 이 아닌데,
///  일관성이 깨진 부분이며 어차피 현재 쓰이지 않는 코드다)
class Util {
  /// iOS 프레임 데이터 앞부분에 붙어 있는 헤더 크기(바이트).
  /// 실제 픽셀은 이 위치부터 시작하므로 건너뛰어야 한다.
  static var IOS_BYTES_OFFSET = 28;

  /// **iOS 전용.** BGRA8888 프레임을 `img.Image` 로 변환한다.
  ///
  /// BGRA는 이미 픽셀 단위 색상 정보라 계산 없이 메모리를 그대로 넘겨주면 된다.
  /// 그래서 아래 NV21 변환보다 훨씬 빠르다.
  static img.Image convertBGRA8888ToImage(CameraImage cameraImage) {
    // BGRA는 모든 데이터가 plane 하나에 들어 있다.
    final plane = cameraImage.planes[0];

    return img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: plane.bytes.buffer,
      // rowStride: 한 줄이 차지하는 실제 바이트 수.
      // 정렬(padding) 때문에 width*4 보다 클 수 있어서 반드시 넘겨야 한다.
      rowStride: plane.bytesPerRow,
      bytesOffset: IOS_BYTES_OFFSET,
      // 바이트가 B,G,R,A 순서로 들어 있다고 알려준다.
      order: img.ChannelOrder.bgra,
    );
  }

  /// **Android 전용.** NV21(YUV) 프레임을 RGB `img.Image` 로 변환한다.
  ///
  /// NV21 구조: 앞쪽에 밝기(Y)가 픽셀 수만큼, 그 뒤에 색상(V,U)이
  /// 가로·세로 각각 절반 해상도로 붙어 있다.
  /// 아래 코드는 정수 연산만으로 YUV → RGB 공식을 계산해 속도를 높인 방식이다.
  /// (1192, 1634 같은 숫자는 실수 계수를 1024배 해서 정수로 만든 값이다)
  ///
  /// ⚠️ 모든 픽셀을 Dart 코드로 도는 방식이라 **느리다.**
  /// 프레임이 밀린다면 카메라 해상도(ResolutionPreset)를 낮추거나
  /// `compute()` 로 별도 isolate에서 돌리는 것을 고려하자.
  static img.Image convertNV21(CameraImage image) {
    final width = image.width.toInt();
    final height = image.height.toInt();

    // NV21은 Y와 UV가 한 덩어리로 들어온다.
    // 그래서 planes 가 하나뿐이고, `planes[0]` 안에 밝기와 색상이 모두 있다.
    // (화면들의 getInputImage() 가 `planes.length != 1` 이면 포기하는 이유가 이것이다)
    Uint8List yuv420sp = image.planes[0].bytes;

    final outImg = img.Image(height: height, width: width);
    // 밝기(Y) 데이터의 총 길이. 이 위치부터 색상(UV) 데이터가 시작된다.
    final int frameSize = width * height;

    // j = 세로 위치, yp = 지금 읽고 있는 Y 값의 인덱스
    for (int j = 0, yp = 0; j < height; j++) {
      // uvp = 이 줄에 해당하는 색상 데이터 위치.
      // `j >> 1` 은 j ~/ 2 와 같다 (색상은 세로로 2줄당 1개만 있으므로).
      int uvp = frameSize + (j >> 1) * width, u = 0, v = 0;
      // i = 가로 위치. i 와 yp 가 함께 1씩 증가한다.
      for (int i = 0; i < width; i++, yp++) {
        // 밝기 값. NV21의 Y는 16부터 시작하므로 16을 뺀다.
        // `0xff &` 는 하위 8비트만 남기라는 뜻으로, 값이 0~255 범위임을 보장한다.
        int y = (0xff & yuv420sp[yp]) - 16;
        if (y < 0) y = 0;
        // 색상은 가로로도 2픽셀당 1개라 짝수 번째 픽셀에서만 새로 읽는다.
        // (홀수 번째는 직전에 읽은 u, v 를 그대로 재사용)
        if ((i & 1) == 0) {
          v = (0xff & yuv420sp[uvp++]) - 128;
          u = (0xff & yuv420sp[uvp++]) - 128;
        }
        // YUV → RGB 변환 공식. 원래는 소수점 계산이지만,
        // 계수를 1024배 해서 정수만으로 계산한다(정수 연산이 훨씬 빠르다).
        //   실수 버전:  R = 1.164*Y + 1.596*V
        //   정수 버전:  R = 1192*Y + 1634*V   (= 실수 계수 × 1024)
        // 따라서 아래 r, g, b 는 실제 색상 값의 **1024배** 상태다.
        // 마지막에 setPixelRgb 로 넘길 때 다시 나눠 0~255 로 되돌린다.
        int y1192 = 1192 * y;
        int r = (y1192 + 1634 * v);
        int g = (y1192 - 833 * v - 400 * u);
        int b = (y1192 + 2066 * u);

        // 계산 결과가 표현 가능한 범위를 벗어나지 않도록 잘라낸다.
        // (262143 = 0~255 를 1024배 확대한 값의 최대치)
        if (r < 0)
          r = 0;
        else if (r > 262143)
          r = 262143;
        if (g < 0)
          g = 0;
        else if (g > 262143)
          g = 262143;
        if (b < 0)
          b = 0;
        else if (b > 262143)
          b = 262143;

        // I don't know how these r, g, b values are defined, I'm just copying what you had bellow and
        // getting their 8-bit values.
        // 1024배 확대해 뒀던 값을 다시 0~255 범위로 되돌려 픽셀에 기록한다.
        //
        // 비트 연산이 복잡해 보이지만 세 줄 모두 결국 **1024로 나누기**다.
        //   ((r << 6) & 0xff0000) >> 16  →  r을 왼쪽 6칸, 다시 오른쪽 16칸 = r >> 10
        //   ((g >> 2) & 0xff00) >> 8     →  g >> 2 후 다시 >> 8         = g >> 10
        //   (b >> 10) & 0xff             →  b >> 10
        // (`>> 10` 은 2¹⁰ = 1024 로 나누는 것과 같다. 중간의 `&` 는 원하는
        //  8비트만 남겨 다른 자리 값이 섞이지 않게 하는 안전장치다)
        // 굳이 세 줄의 표현 방식이 다른 이유는 없다. 원본 코드를 그대로 옮긴 것이다.
        outImg.setPixelRgb(
          i,
          j,
          ((r << 6) & 0xff0000) >> 16,
          ((g >> 2) & 0xff00) >> 8,
          (b >> 10) & 0xff,
        );
      }
    }
    return outImg;
  }

  // TODO method to convert CameraImage to Image
  /// YUV420(3-plane) 프레임을 변환하는 대안 구현.
  ///
  /// ⚠️ **현재 이 프로젝트에서는 사용하지 않는다.**
  /// 두 카메라 화면이 `ImageFormatGroup.nv21` / `bgra8888` 로 고정되어 있어
  /// 이 형식의 프레임이 들어올 일이 없기 때문이다.
  ///
  /// ⚠️ 게다가 아래 코드에는 버그가 있다. `setPixelR` 은 빨강 채널만 설정하는
  /// 함수인데 여기에 RGBA가 합쳐진 값을 넣고 있어서, 살려 쓰려면 수정이 필요하다.
  /// (`static` 이 아니라서 쓰려면 `Util().convertYUV420ToImage(...)` 처럼
  ///  객체를 만들어야 하는 점도 다르다)
  img.Image convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    // YUV420은 Y / U / V 가 각각 다른 plane 에 나뉘어 들어온다.
    final yRowStride = cameraImage.planes[0].bytesPerRow;
    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    final image = img.Image(width: width, height: height);

    for (var w = 0; w < width; w++) {
      for (var h = 0; h < height; h++) {
        // 색상은 가로·세로 절반 해상도라 좌표를 2로 나눠서 찾는다.
        final uvIndex =
            uvPixelStride * (w / 2).floor() + uvRowStride * (h / 2).floor();
        // (아래 index 는 계산만 하고 실제로 쓰이지 않는다 — analyze 경고 대상)
        final index = h * width + w;
        final yIndex = h * yRowStride + w;

        final y = cameraImage.planes[0].bytes[yIndex];
        final u = cameraImage.planes[1].bytes[uvIndex];
        final v = cameraImage.planes[2].bytes[uvIndex];

        image.data!.setPixelR(w, h, yuv2rgb(y, u, v)); //= yuv2rgb(y, u, v);
      }
    }
    return image;
  }

  /// YUV 픽셀 하나를 ARGB 정수 하나로 바꾼다.
  /// 위 `convertYUV420ToImage` 에서만 사용하는 보조 함수다.
  int yuv2rgb(int y, int u, int v) {
    // Convert yuv pixel to rgb
    // 표준 YUV→RGB 변환 공식.
    var r = (y + v * 1436 / 1024 - 179).round();
    var g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
    var b = (y + u * 1814 / 1024 - 227).round();

    // Clipping RGB values to be inside boundaries [ 0 , 255 ]
    // clamp: 값이 범위를 벗어나면 경계값으로 맞춰준다.
    r = r.clamp(0, 255);
    g = g.clamp(0, 255);
    b = b.clamp(0, 255);

    // 네 값을 32비트 정수 하나로 합친다 (앞 8비트 0xff 는 불투명 alpha).
    return 0xff000000 |
        ((b << 16) & 0xff0000) |
        ((g << 8) & 0xff00) |
        (r & 0xff);
  }
}
