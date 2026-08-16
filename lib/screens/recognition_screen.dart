// Platform.isAndroid / Platform.isIOS 로 현재 OS를 판별하기 위해 필요하다.
import 'dart:io';

// ImageFilter (배경 흐림 효과) 를 쓰기 위해 필요하다.
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

// DeviceOrientation (기기 방향) 을 쓰기 위해 필요하다.
import 'package:flutter/services.dart';
import 'package:flutter_face_recognition_realtime/ml/recognizer.dart';
import 'package:flutter_face_recognition_realtime/util.dart';

// ML Kit 얼굴 검출. "사진 속 어디에 얼굴이 있는가"를 찾아준다.
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

// 전역 변수 cameras 를 쓰기 위해 main.dart 를 가져온다.
import '../main.dart';
import '../ml/recognition.dart';

/// **실시간 얼굴 인식 화면.** 카메라에 잡힌 얼굴이 등록된 누구인지 찾아 표시한다.
///
/// ⚠️ **이 화면도 아직 미완성이며 직접 채워 넣어야 한다.**
/// 등록 화면(`registration_screen.dart`)과 구조가 거의 같지만 목적이 다르다.
///
/// | | 등록 화면 | 이 화면(인식) |
/// |---|---|---|
/// | 목적 | 얼굴을 **DB에 저장** | 저장된 얼굴과 **비교해 이름 표시** |
/// | 버튼 | 등록 버튼을 눌렀을 때만 처리 | 매 프레임 자동 처리 |
/// | 화면 표시 | 이름 입력 다이얼로그 | 얼굴 위 사각형 + 이름표 |
///
/// **완성하려면:**
/// 1. `FaceDetector` 와 `Recognizer` 를 선언하고 `initState()` 에서 생성
/// 2. `doFaceDetectionOnFrame()` 에서 얼굴 검출
/// 3. 검출된 얼굴마다 잘라내어 `recognizer.recognize()` 호출 → `recognitions` 에 저장
/// 4. `buildResult()` 주석을 풀어 결과를 화면에 그리기
class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  /// 카메라를 제어하는 객체. (`CameraController?` 로 두는 편이 더 안전하다)
  dynamic controller;

  /// 프레임 하나를 처리 중인지 나타내는 깃발.
  ///
  /// 카메라는 초당 수십 장을 보내는데 인식은 그보다 느리다.
  /// 처리 중 들어온 프레임은 버려서 밀리지 않게 한다.
  ///
  /// ⚠️ 처리 후 `isBusy = false` 로 되돌리는 것을 빠뜨리면 화면이 멈춘 것처럼 보인다.
  bool isBusy = false;

  /// 화면 크기. build() 에서 채운다.
  late Size size;

  /// 현재 사용 중인 카메라. `cameras[1]` 은 보통 전면 카메라다.
  /// ⚠️ 카메라가 하나뿐인 기기/시뮬레이터에서는 존재하지 않아 앱이 죽는다.
  late CameraDescription description = cameras[1];

  /// 현재 카메라가 전면인지 후면인지.
  CameraLensDirection camDirec = CameraLensDirection.front;

  /// **이번 프레임의 인식 결과 목록.**
  ///
  /// 이 화면의 핵심 데이터다. 얼굴마다 이름과 위치, 유사도가 들어간다.
  /// `FaceDetectorPainter` 가 이 목록을 받아 화면에 사각형과 이름표를 그린다.
  /// (아직 채우는 코드가 없어 지금은 항상 비어 있다)
  late List<Recognition> recognitions = [];

  //TODO declare face detector
  late FaceDetector faceDetector;

  //TODO declare face recognizer
  late Recognizer recognizer;

  /// 화면이 처음 만들어질 때 한 번 호출된다.
  @override
  void initState() {
    super.initState();

    //TODO initialize face detector
    FaceDetectorOptions options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
    );
    faceDetector = FaceDetector(options: options);

    //TODO initialize face recognizer
    recognizer = Recognizer();

    //TODO initialize camera footage
    initializeCamera();
  }

  //TODO code to initialize the camera feed
  /// 카메라를 켜고 프레임을 계속 받아오기 시작한다.
  initializeCamera() async {
    controller = CameraController(
      description,
      // 해상도. 프레임이 버벅이면 low 로 낮춰보자.
      ResolutionPreset.medium,
      // 프레임 포맷을 OS별로 다르게 지정한다.
      // ⚠️ yuv420 등으로 바꾸면 getInputImage() 가 조용히 null 을 돌려주어
      //    아무 에러 없이 얼굴 검출이 동작하지 않게 된다.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup
                .nv21 // for Android
          : ImageFormatGroup.bgra8888,
      // 소리는 필요 없으므로 끈다.
      enableAudio: false,
    ); // for iOS);

    await controller.initialize().then((_) {
      // 준비되는 동안 사용자가 화면을 나갔다면 여기서 중단한다.
      // (사라진 화면에 setState 를 부르면 에러가 난다)
      if (!mounted) {
        return;
      }
      // 미리보기를 표시하기 위해 화면을 다시 그린다.
      setState(() {
        controller;
      });

      // 프레임이 들어올 때마다 아래 함수가 호출된다.
      // isBusy 면 무시하고, 아니면 깃발을 세운 뒤 검출을 시작한다.
      // 풀어 쓰면 이렇다:
      //   (image) {
      //     if (!isBusy) {
      //       isBusy = true;
      //       frame = image;
      //       doFaceDetectionOnFrame();
      //     }
      //   }
      controller.startImageStream(
        (image) => {
          if (!isBusy) {isBusy = true, frame = image, doFaceDetectionOnFrame()},
        },
      );
    });
  }

  //TODO close all resources
  /// 화면이 사라질 때 카메라를 끈다.
  ///
  /// 💡 faceDetector 와 recognizer 를 추가했다면 여기서 함께 정리해야 한다.
  ///    예) faceDetector.close(); recognizer.close();
  @override
  void dispose() {
    controller?.dispose();
    faceDetector.close();
    recognizer.close();
    // super.dispose() 는 항상 **마지막에** 호출하는 것이 규칙이다.
    super.dispose();
  }

  //TODO face detection on a frame
  /// 검출된 얼굴 목록. (아직 채우는 코드가 없어 항상 null 이다)
  dynamic _scanResults;

  /// 가장 최근에 받은 카메라 프레임 한 장.
  CameraImage? frame;

  /// 프레임 한 장에서 얼굴을 찾고 누구인지 알아낸다. **핵심 실습 구간이다.**
  ///
  /// 완성 예시:
  /// ```dart
  /// final inputImage = getInputImage();
  /// if (inputImage == null) {
  ///   setState(() => isBusy = false);
  ///   return;
  /// }
  /// final faces = await faceDetector.processImage(inputImage);
  /// performFaceRecognition(faces);
  /// ```
  ///
  /// ⚠️ 어떤 경로로 끝나든 반드시 `isBusy = false` 가 되어야 한다.
  doFaceDetectionOnFrame() async {
    //TODO convert frame into InputImage format
    InputImage? inputImage = getInputImage();
    if (inputImage == null) {
      setState(() {
        isBusy = false;
      });
      return;
    }

    //TODO pass InputImage to face detection model and detect faces
    List<Face> faces = await faceDetector.processImage(inputImage);
    print('faces=' + faces.length.toString());

    //TODO perform face recognition on detected faces
    performFaceRecognition(faces);

    // isBusy 를 내리고 _scanResults 에 결과를 담는 일은
    // performFaceRecognition() 끝부분의 setState 가 대신 처리한다.
    // 그래서 여기서는 아무것도 하지 않는다. (중복 setState 방지)
    //
    // ⚠️ 단, performFaceRecognition() 이 도중에 예외로 빠져나가면
    //    isBusy 가 true 로 남아 이후 모든 프레임이 무시된다.
    //    안전하게 하려면 try/finally 로 감싸 finally 에서 내려주는 것이 좋다.
    // setState(() {
    //   isBusy = false;
    //   _scanResults = faces;
    // });
  }

  // ─────────────────────────────────────────────────────────────
  // 아래 주석 처리된 performFaceRecognition() 이 실습의 정답에 가까운 코드다.
  // 주석을 풀고 필요한 import(`../util.dart`, `../ml/recognizer.dart`,
  // `package:image/image.dart` 등)를 다시 추가하면 된다.
  //
  //   ① 카메라 프레임을 img.Image 로 변환 (OS별로 다른 함수)
  //   ② 세로 방향이 되도록 회전 (전면 270도 / 후면 90도)
  //   ③ 얼굴 사각형대로 잘라내기(crop)
  //   ④ recognizer.recognize() 로 누구인지 판별
  //   ⑤ 결과를 recognitions 에 담아 화면에 그리기
  //
  // 참고: 아래 코드는 등록 화면에서 복사해 온 것이라 `register` 깃발과
  //       등록 다이얼로그가 섞여 있다. 인식 화면에서는 그 부분이 필요 없으니
  //       ①~④ 만 남기고 결과를 recognitions 에 넣도록 고쳐 쓰면 된다.
  // ─────────────────────────────────────────────────────────────

  img.Image? image;

  //TODO perform Face Recognition
  performFaceRecognition(List<Face> faces) async {
    recognitions.clear();

    //TODO convert CameraImage to Image and rotate it so that our frame will be in a portrait
    image = Platform.isIOS
        ? Util.convertBGRA8888ToImage(frame!)
        : Util.convertNV21(frame!);
    image = img.copyRotate(
      image!,
      angle: camDirec == CameraLensDirection.front ? 270 : 90,
    );

    for (Face face in faces) {
      Rect faceRect = face.boundingBox;
      //TODO crop face
      img.Image croppedFace = img.copyCrop(
        image!,
        x: faceRect.left.toInt(),
        y: faceRect.top.toInt(),
        width: faceRect.width.toInt(),
        height: faceRect.height.toInt(),
      );

      //TODO pass cropped face to face recognition model
      Recognition recognition = await recognizer.recognize(
        croppedFace,
        faceRect,
      );

      if (recognition.distance < 0.3) {
        recognition.name = 'Unknown';
      }

      recognitions.add(recognition);
    }

    setState(() {
      isBusy = false;
      _scanResults = recognitions;
    });
  }

  // //TODO convert CameraImage to InputImage
  /// 기기 방향을 각도로 바꾸기 위한 대응표.
  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// 카메라 프레임(`frame`)을 ML Kit이 이해하는 `InputImage` 로 변환한다.
  ///
  /// **이미 완성되어 있으므로 그대로 호출해서 쓰면 된다.**
  ///
  /// ⚠️ 변환할 수 없으면 예외 대신 **조용히 `null`** 을 돌려준다.
  /// 얼굴 검출이 아무 에러 없이 동작하지 않는다면 여기부터 의심하자.
  InputImage? getInputImage() {
    final camera = camDirec == CameraLensDirection.front
        ? cameras[1]
        : cameras[0];
    // 카메라 센서가 물리적으로 몇 도 돌아가 붙어 있는지 (보통 90 또는 270).
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      // iOS는 센서 방향을 그대로 쓰면 된다.
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      // Android는 센서 방향 + 기기를 들고 있는 방향을 함께 계산해야 한다.
      var rotationCompensation =
          _orientations[controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        // 전면 카메라는 거울처럼 반전되어 있어 각도를 더한다.
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        // 후면 카메라는 빼준다. (+360 은 음수 방지용)
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    // 프레임 포맷이 기대한 것인지 확인한다.
    final format = InputImageFormatValue.fromRawValue(frame!.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888))
      return null;

    // NV21/BGRA8888 은 데이터가 plane 하나에 들어 있어야 정상이다.
    if (frame!.planes.length != 1) return null;
    final plane = frame!.planes.first;

    // 바이트 배열 + 부가 정보(크기/회전/포맷)를 묶어 ML Kit에 넘길 형태로 만든다.
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(frame!.width.toDouble(), frame!.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // TODO Show rectangles around detected faces
  /// 인식 결과를 얼굴 위 사각형 + 이름표로 그리는 레이어를 만든다.
  ///
  /// build() 의 Stack 에서 카메라 프리뷰 위에 얹어 사용한다.
  ///
  /// ⚠️ imageSize 에 previewSize 의 width/height 를 **바꿔서** 넘기는 것에 주의.
  ///    카메라 프레임이 가로로 누워 들어오기 때문이다.
  ///    사각형 위치가 어긋난다면 여기를 먼저 의심하자.
  Widget buildResult() {
    if (_scanResults == null ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(child: Text('Camera is not initialized'));
    }
    final Size imageSize = Size(
      controller.value.previewSize!.height,
      controller.value.previewSize!.width,
    );
    CustomPainter painter = FaceDetectorPainter(
      imageSize,
      _scanResults,
      camDirec,
    );
    return CustomPaint(painter: painter);
  }

  //TODO toggle camera direction
  /// 전면 ↔ 후면 카메라를 전환한다.
  void _toggleCameraDirection() async {
    if (camDirec == CameraLensDirection.back) {
      camDirec = CameraLensDirection.front;
      description = cameras[1];
    } else {
      camDirec = CameraLensDirection.back;
      description = cameras[0];
    }
    // 스트림을 먼저 멈추지 않으면 카메라를 다시 열 때 충돌이 난다.
    await controller.stopImageStream();
    setState(() {
      controller;
    });
    // 바뀐 description 으로 카메라를 새로 연다.
    initializeCamera();
  }

  /// 화면을 그린다. setState 가 호출될 때마다 다시 실행된다.
  @override
  Widget build(BuildContext context) {
    // 겹쳐 쌓을 위젯들을 담을 목록. 나중에 넣은 것이 위에 그려진다.
    List<Widget> stackChildren = [];
    size = MediaQuery.of(context).size;

    // controller 가 아직 null 일 수 있으므로(카메라 준비 전) 확인한다.
    if (controller != null) {
      //TODO View for displaying the live camera footage
      // ── 1층: 카메라 미리보기 ──
      stackChildren.add(
        Positioned(
          top: 0.0,
          left: 0.0,
          width: size.width,
          height: size.height,
          child: Container(
            child: (controller.value.isInitialized)
                ? AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  )
                : Container(),
          ),
        ),
      );

      //TODO View for displaying rectangles around detected aces
      stackChildren.add(
        Positioned(
          top: 0.0,
          left: 0.0,
          width: size.width,
          height: size.height,
          child: buildResult(),
        ),
      );
    }

    //TODO View for displaying the bar to switch camera direction or for registering faces
    // ── 맨 위층: 하단 반투명 버튼 바 ──
    // controller 와 무관하게 항상 표시되므로 if 문 바깥에 있다.
    stackChildren.add(
      Positioned(
        bottom: 40,
        left: 20,
        right: 20,
        // ClipRRect + BackdropFilter 조합이 "뒤가 흐릿하게 비치는" 유리 효과를 만든다.
        // ClipRRect 로 잘라주지 않으면 흐림 효과가 화면 전체에 번진다.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            // sigma 값이 클수록 더 뿌옇게 흐려진다.
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withAlpha(80),
                borderRadius: BorderRadius.circular(20),
                // 참고: withOpacity 는 최신 Flutter에서 deprecated 되었다.
                // `withValues(alpha: 0.2)` 로 바꾸면 경고가 사라진다.
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 카메라 전환 버튼
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: IconButton(
                      icon: Icon(Icons.cached, color: Colors.white),
                      iconSize: 40,
                      color: Colors.black,
                      onPressed: () {
                        _toggleCameraDirection();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 지금까지 모은 위젯들을 Stack 으로 겹쳐 최종 화면을 만든다.
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          margin: const EdgeInsets.only(top: 0),
          color: Colors.black,
          child: Stack(children: stackChildren),
        ),
      ),
    );
  }
}

/// 인식된 얼굴 위에 **사각형 + 이름표**를 직접 그리는 클래스.
///
/// `CustomPainter` 는 위젯 조합 대신 캔버스에 선/도형/글자를 직접 그릴 때 쓴다.
/// 얼굴 위치가 매 프레임 달라지므로 위젯보다 이 방식이 적합하다.
///
/// `buildResult()` 가 이 클래스를 CustomPaint 에 물려 화면에 얹는다.
///
/// 참고: 등록 화면(registration_screen.dart)에도 같은 이름의 클래스가 있지만
/// **다른 클래스**다. 저쪽은 ML Kit의 `Face` 를 받아 사각형만 그리고,
/// 이쪽은 `Recognition` 을 받아 이름과 유사도까지 표시한다.
class FaceDetectorPainter extends CustomPainter {
  /// 카메라 원본 이미지의 크기. 좌표 변환의 기준이 된다.
  final Size absoluteImageSize;

  /// 그릴 인식 결과 목록.
  final List<Recognition> faces;

  /// 전면/후면 여부. 전면이면 좌우를 뒤집어 그려야 한다.
  final CameraLensDirection camDirection;

  FaceDetectorPainter(this.absoluteImageSize, this.faces, this.camDirection);

  /// 실제로 그리는 함수. [size] 는 그림을 그릴 화면 영역의 크기다.
  @override
  void paint(Canvas canvas, Size size) {
    // 원본 이미지 좌표 → 화면 좌표로 바꾸기 위한 배율.
    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;

    // 얼굴 테두리용 붓. `..` 은 같은 객체에 설정을 연달아 적용하는 cascade 문법이다.
    final Paint boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.deepPurple.shade300;

    // 이름표 배경용 붓 (반투명 보라).
    final Paint labelBgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.deepPurple.shade300.withAlpha(150);

    for (final face in faces) {
      // 전면 카메라는 거울처럼 좌우가 반전되어 보이므로
      // (전체 너비 - 오른쪽) 을 왼쪽으로 삼아 x 좌표를 뒤집는다.
      final double left = camDirection == CameraLensDirection.front
          ? (absoluteImageSize.width - face.location.right) * scaleX
          : face.location.left * scaleX;
      // 위아래는 뒤집을 필요가 없다.
      final double top = face.location.top * scaleY;
      final double right = camDirection == CameraLensDirection.front
          ? (absoluteImageSize.width - face.location.left) * scaleX
          : face.location.right * scaleX;
      final double bottom = face.location.bottom * scaleY;

      // ① 얼굴 둘레에 모서리가 둥근 사각형을 그린다.
      final rect = Rect.fromLTRB(left, top, right, bottom);
      final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rRect, boxPaint);

      // Draw name label
      // ② 이름표 문자열을 만든다. 예: "홍길동 (0.87)"
      // 괄호 안 숫자는 코사인 유사도이며 1.0 에 가까울수록 확신이 높다는 뜻이다.
      final String label = face.name.isNotEmpty
          ? '${face.name} (${face.distance.toStringAsFixed(2)})'
          : 'Unknown';

      // 캔버스에 글자를 그리려면 TextSpan(내용) + TextPainter(그리는 도구) 가 필요하다.
      final textSpan = TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      );

      // layout() 을 호출해야 글자의 실제 가로/세로 크기가 계산된다.
      // 이 크기를 알아야 아래에서 배경 상자를 딱 맞게 그릴 수 있다.
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.6);

      final double labelPadding = 6;
      final double labelX = left;
      // 기본적으로 얼굴 사각형 **위쪽**에 이름표를 놓는다.
      final double labelY = top - textPainter.height - 8;

      final backgroundRect = Rect.fromLTWH(
        labelX,
        // 얼굴이 화면 맨 위에 있으면 이름표가 화면 밖으로 나가버리므로,
        // 그럴 때는 사각형 안쪽(top + 4)으로 내려 그린다.
        labelY < 0 ? top + 4 : labelY,
        textPainter.width + labelPadding * 2,
        textPainter.height + labelPadding,
      );

      // ③ 글자 뒤에 반투명 배경을 먼저 깔고
      canvas.drawRRect(
        RRect.fromRectAndRadius(backgroundRect, const Radius.circular(8)),
        labelBgPaint,
      );

      // ④ 그 위에 글자를 그린다. (순서가 반대면 글자가 배경에 가려진다)
      textPainter.paint(
        canvas,
        Offset(
          backgroundRect.left + labelPadding,
          backgroundRect.top + labelPadding / 2,
        ),
      );
    }
  }

  /// 다시 그릴지 여부. 매 프레임 결과가 바뀌므로 항상 true 다.
  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) => true;
}
