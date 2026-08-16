// Platform.isAndroid / Platform.isIOS 로 현재 OS를 판별하기 위해 필요하다.
import 'dart:io';

// ImageFilter (배경 흐림 효과) 를 쓰기 위해 필요하다.
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

// DeviceOrientation (기기 방향) 을 쓰기 위해 필요하다.
import 'package:flutter/services.dart';
import 'package:flutter_face_recognition_realtime/util.dart';

// ML Kit 얼굴 검출. "사진 속 어디에 얼굴이 있는가"를 찾아준다.
// (누구인지 알아내는 것은 ML Kit이 아니라 우리 FaceNet 모델의 몫이다)
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// 이미지 회전/자르기용. Flutter 의 Image 위젯과 이름이 겹치므로
// `as img` 별칭을 붙여 img.Image 처럼 구분해서 쓴다.
import 'package:image/image.dart' as img;

// 전역 변수 cameras 를 쓰기 위해 main.dart 를 가져온다.
import '../main.dart';
import '../ml/recognition.dart';

/// **얼굴 등록 화면.** 카메라로 얼굴을 찍어 이름과 함께 DB에 저장한다.
///
/// ⚠️ **이 화면은 아직 미완성이며, 직접 채워 넣어야 하는 실습 과제다.**
/// 현재 동작하는 것은 카메라 미리보기와 전/후면 전환뿐이고,
/// 얼굴 검출·인식·등록 로직은 `//TODO` 주석과 주석 처리된 코드로만 남아 있다.
///
/// **완성하려면 대략 이런 순서로 진행한다:**
/// 1. 아래 "declare face detector" 자리에 `FaceDetector` 와 `Recognizer` 를 선언
/// 2. `initState()` 에서 그 둘을 생성
/// 3. `doFaceDetectionOnFrame()` 안을 채워 얼굴을 검출
/// 4. 주석 처리된 `performFaceRecognition()` 을 살려 얼굴을 잘라내고 임베딩 추출
/// 5. 주석 처리된 `showFaceRegistrationDialogue()` 를 살려 이름을 입력받고 저장
/// 6. 하단 얼굴 아이콘 버튼의 빈 `onPressed` 에 `register = true;` 를 연결
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  // 참고: State 클래스 이름이 _RegistrationScreenState 가 아니라
  // _RecognitionScreenState 인데, 인식 화면에서 복사해 만들면서 이름을 안 바꾼 것이다.
  // 동작에는 문제가 없지만 헷갈리므로 이름을 바꿔주면 더 좋다.
  @override
  State<RegistrationScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RegistrationScreen> {
  /// 카메라를 제어하는 객체.
  ///
  /// 원래는 `CameraController?` 타입이어야 맞지만 `dynamic` 으로 되어 있다.
  /// dynamic 은 아무 타입이나 담을 수 있는 대신 **오타를 컴파일 시점에 못 잡는다.**
  /// (`controller.startImagStream()` 처럼 잘못 써도 실행 전까지 모른다)
  /// 익숙해지면 `CameraController?` 로 바꾸는 것을 권한다.
  dynamic controller;

  /// 지금 프레임 하나를 처리하는 중인지 나타내는 깃발.
  ///
  /// 카메라는 초당 수십 장을 쏟아내는데 얼굴 검출은 그보다 느리다.
  /// 처리 중일 때 들어온 프레임은 그냥 버려서 밀리지 않게 하는 장치다.
  ///
  /// ⚠️ **가장 흔한 실수**: 처리를 끝낸 뒤 `isBusy = false` 로 되돌리는 것을
  /// 빠뜨리면 이후 모든 프레임이 무시되어 화면이 멈춘 것처럼 보인다.
  bool isBusy = false;

  /// 화면 크기. build() 에서 채워 넣어 다른 곳에서 재사용한다.
  late Size size;

  /// 현재 사용 중인 카메라. `cameras[1]` 은 보통 전면 카메라다.
  ///
  /// ⚠️ 카메라가 하나뿐인 기기나 시뮬레이터에서는 [1] 이 존재하지 않아
  /// 앱이 바로 죽는다. 실제 배포용이라면 목록을 확인하고 고르는 코드가 필요하다.
  late CameraDescription description = cameras[1];

  /// 현재 카메라가 전면인지 후면인지. 화면에 사각형을 좌우 반전해 그릴 때도 쓰인다.
  CameraLensDirection camDirec = CameraLensDirection.front;

  /// 인식 결과 목록. (현재는 채우는 코드가 아직 없다)
  late List<Recognition> recognitions = [];

  //TODO declare face detector
  late FaceDetector faceDetector;

  //TODO declare face recognizer
  // 예) late Recognizer recognizer;

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
    // 예) recognizer = Recognizer();

    //TODO initialize camera footage
    initializeCamera();
  }

  //TODO code to initialize the camera feed
  /// 카메라를 켜고 프레임을 계속 받아오기 시작한다.
  initializeCamera() async {
    controller = CameraController(
      description,
      // 해상도. 높을수록 선명하지만 처리가 느려진다.
      // 프레임이 버벅이면 low 로 낮춰보자. (low / medium / high / veryHigh ...)
      ResolutionPreset.medium,
      // 프레임 포맷을 OS별로 다르게 지정한다. 이 프로젝트 전체가 이 두 가지를
      // 전제로 만들어져 있으니 함부로 바꾸면 안 된다.
      // 특히 yuv420 으로 바꾸면 아래 getInputImage() 가 조용히 null 을 돌려주어
      // 아무 에러 없이 얼굴 검출이 동작하지 않게 된다.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup
                .nv21 // for Android
          : ImageFormatGroup.bgra8888,
      // 얼굴 인식에 소리는 필요 없으므로 끈다. (마이크 권한 요청도 피할 수 있다)
      enableAudio: false,
    ); // for iOS);

    // 카메라 준비는 시간이 걸리므로 기다린다.
    await controller.initialize().then((_) {
      // mounted: 이 화면이 아직 살아 있는지 여부.
      // 준비되는 동안 사용자가 뒤로가기를 눌렀다면 setState 를 부르면 에러가 나므로
      // 여기서 빠져나간다. 비동기 처리 후에는 항상 확인하는 습관을 들이자.
      if (!mounted) {
        return;
      }
      // 컨트롤러가 준비됐으니 화면을 다시 그려 미리보기를 표시한다.
      // (setState 안의 `controller;` 한 줄은 실제로 아무 일도 하지 않는다.
      //  화면 갱신 자체가 목적이라 `setState(() {});` 와 같은 뜻이다)
      setState(() {
        controller;
      });

      // 여기서부터 카메라 프레임이 계속 흘러들어온다.
      // 아래 화살표 함수는 프레임이 들어올 때마다 호출된다.
      //   - isBusy 면 그냥 무시하고 (프레임 버리기)
      //   - 아니면 isBusy 를 세우고, 프레임을 frame 에 보관한 뒤 검출을 시작한다.
      // `{...}` 안에 콤마로 나열한 것은 Dart의 집합(Set) 리터럴을 이용한 축약 표기다.
      // 읽기 어렵다면 아래처럼 풀어 써도 완전히 같다:
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
  /// 화면이 사라질 때 카메라를 반드시 꺼준다.
  ///
  /// 이걸 빼먹으면 화면을 나가도 카메라가 계속 켜져 있어 배터리를 먹고,
  /// 다음에 다시 들어올 때 카메라를 못 여는 문제가 생긴다.
  ///
  /// ML Kit 검출기도 네이티브 자원을 잡고 있으므로 함께 닫아야 한다.
  /// 닫지 않으면 화면을 드나들 때마다 검출기가 쌓여 메모리가 계속 늘어난다.
  ///
  /// 💡 나중에 recognizer 를 추가하면 여기서 함께 정리해야 한다.
  ///    예) recognizer.close();
  @override
  void dispose() {
    controller?.dispose();
    faceDetector.close();
    // super.dispose() 는 항상 **마지막에** 호출하는 것이 규칙이다.
    super.dispose();
  }

  //TODO face detection on a frame
  /// 검출된 얼굴 목록을 담아둘 변수. (아직 채우는 코드가 없어 항상 null 이다)
  dynamic _scanResults;

  /// 가장 최근에 카메라에서 받은 프레임 한 장.
  CameraImage? frame;

  /// 프레임 한 장에서 얼굴을 찾아내는 함수. **여기가 핵심 실습 구간이다.**
  ///
  /// 완성 예시:
  /// ```dart
  /// final inputImage = getInputImage();          // 1. ML Kit 입력 형식으로 변환
  /// if (inputImage == null) {                    //    변환 실패 시 그냥 넘어간다
  ///   setState(() => isBusy = false);
  ///   return;
  /// }
  /// final faces = await faceDetector.processImage(inputImage);  // 2. 얼굴 검출
  /// performFaceRecognition(faces);               // 3. 인식/등록 처리
  /// ```
  ///
  /// ⚠️ 어떤 경로로 함수가 끝나든 반드시 `isBusy = false` 가 되어야 한다.
  /// 중간에 return 하는 분기를 만들었다면 거기서도 꼭 되돌려 놓자.
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
  // 아래 두 개의 주석 처리된 함수가 "3단계 실습"의 정답에 가까운 코드다.
  // 주석을 풀고 필요한 import(`../util.dart`, `../ml/recognizer.dart`,
  // `package:image/image.dart` 등)를 다시 추가하면 동작한다.
  //
  // performFaceRecognition() 이 하는 일:
  //   ① 카메라 프레임을 img.Image 로 변환 (OS별로 다른 함수 사용)
  //   ② 세로 방향이 되도록 회전 (전면 270도 / 후면 90도)
  //   ③ 검출된 얼굴 사각형대로 잘라내기(crop)
  //   ④ 잘라낸 얼굴을 recognizer 에 넣어 임베딩 추출
  //   ⑤ 이름 입력 다이얼로그 띄우기
  // ─────────────────────────────────────────────────────────────

  img.Image? image;
  bool register = false;

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

    if (register) {
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

        //TODO show face registration dialogue
      }

      register = false;
    }

    setState(() {
      isBusy = false;
      _scanResults = faces;
    });
  }

  //TODO Face Registration Dialogue
  // TextEditingController textEditingController = TextEditingController();
  // showFaceRegistrationDialogue(img.Image croppedFace, Recognition recognition){
  //   showDialog(
  //     context: context,
  //     builder: (ctx) => Dialog(
  //       backgroundColor: Colors.transparent,
  //       insetPadding: const EdgeInsets.symmetric(
  //         horizontal: 20,
  //         vertical: 60,
  //       ),
  //       child: ClipRRect(
  //         borderRadius: BorderRadius.circular(20),
  //         child: BackdropFilter(
  //           filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
  //           child: Container(
  //             padding: const EdgeInsets.all(20),
  //             decoration: BoxDecoration(
  //               color: Colors.white.withAlpha(30),
  //               borderRadius: BorderRadius.circular(20),
  //               border: Border.all(color: Colors.white.withAlpha(40)),
  //             ),
  //             child: SingleChildScrollView(
  //               child: Column(
  //                 mainAxisSize: MainAxisSize.min,
  //                 children: [
  //                   const Text(
  //                     "Register Your Face",
  //                     textAlign: TextAlign.center,
  //                     style: TextStyle(
  //                       fontSize: 20,
  //                       color: Colors.white,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 20),
  //                   ClipRRect(
  //                     borderRadius: BorderRadius.circular(100),
  //                     child: Image.memory(
  //                       Uint8List.fromList(img.encodeBmp(croppedFace)),
  //                       width: 150,
  //                       height: 150,
  //                       fit: BoxFit.cover,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 20),
  //                   TextField(
  //                     controller: textEditingController,
  //                     style: const TextStyle(color: Colors.white),
  //                     decoration: InputDecoration(
  //                       hintText: "Enter your name",
  //                       hintStyle: const TextStyle(color: Colors.white70),
  //                       filled: true,
  //                       fillColor: Colors.white.withAlpha(80),
  //                       border: OutlineInputBorder(
  //                         borderRadius: BorderRadius.circular(12),
  //                         borderSide: BorderSide.none,
  //                       ),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 20),
  //                   SizedBox(
  //                     width: double.infinity,
  //                     child: ElevatedButton.icon(
  //                       onPressed: () {
  //                         recognizer.registerFaceInDB(
  //                           textEditingController.text.trim(),
  //                           recognition.embeddings,
  //                           Uint8List.fromList(img.encodeBmp(croppedFace!)),
  //                         );
  //                         Navigator.pop(context);
  //                         Navigator.pop(context); // Close dialog
  //                         ScaffoldMessenger.of(context).showSnackBar(
  //                           const SnackBar(
  //                             content: Text("Face Registered"),
  //                           ),
  //                         );
  //                       },
  //                       icon: const Icon(Icons.check),
  //                       label: const Text("Register"),
  //                       style: ElevatedButton.styleFrom(
  //                         backgroundColor: Colors.deepPurple.shade300,
  //                         foregroundColor: Colors.white,
  //                         padding: const EdgeInsets.symmetric(vertical: 14),
  //                         shape: RoundedRectangleBorder(
  //                           borderRadius: BorderRadius.circular(12),
  //                         ),
  //                       ),
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ),
  //         ),
  //       ),
  //     )
  //   );
  // }

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
  /// **이 함수는 이미 완성되어 있으므로 그대로 호출해서 쓰면 된다.**
  /// 회전 각도 계산이 까다로운데(특히 Android 전면 카메라), 그 부분이
  /// 이미 처리되어 있다.
  ///
  /// ⚠️ 변환할 수 없는 상황이면 **예외를 던지지 않고 조용히 `null` 을 돌려준다.**
  /// 얼굴 검출이 아무 에러 없이 동작하지 않는다면 여기서 null 이 나오는지
  /// 먼저 확인해 보자. null 이 나오는 경우는 다음과 같다:
  ///   - 회전 각도를 계산할 수 없을 때
  ///   - 프레임 포맷이 NV21(Android)/BGRA8888(iOS) 이 아닐 때
  ///   - 프레임이 여러 개의 plane 으로 나뉘어 있을 때 (yuv420 등)
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
      // Android는 센서 방향 + 지금 기기를 들고 있는 방향을 함께 계산해야 한다.
      var rotationCompensation =
          _orientations[controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        // 전면 카메라는 거울처럼 좌우가 뒤집혀 있어 각도를 더한다.
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        // 후면 카메라는 빼준다. (+360 은 음수가 되지 않게 하려는 장치)
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    // 프레임 포맷이 우리가 기대한 것인지 확인한다.
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
  // 아래 buildResult() 의 주석을 풀면 검출된 얼굴 위에 사각형이 그려진다.
  // build() 안의 "View for displaying rectangles" 부분 주석도 함께 풀어야 한다.
  // 주의: 여기서 넘기는 imageSize 는 width/height 를 **바꿔서** 전달한다.
  //       카메라 프레임이 가로로 누워 들어오기 때문이다.
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
  ///
  /// 프레임 스트림을 멈춘 뒤 카메라를 다시 초기화하는 방식이다.
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

  /// 화면을 그린다. 값이 바뀌어 setState 가 호출될 때마다 다시 실행된다.
  @override
  Widget build(BuildContext context) {
    // 겹쳐 쌓을 위젯들을 담을 목록.
    // 이렇게 리스트에 순서대로 넣은 뒤 마지막에 Stack 에 통째로 넘기는 방식이다.
    // 나중에 넣은 것이 위에 그려진다.
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
    // 이 부분은 controller 와 무관하게 항상 표시되므로 if 문 바깥에 있다.
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
                // 버튼들을 가로로 균등하게 배치한다.
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
                  // 참고: Row(가로 배치) 안에서는 SizedBox 의 height 가 아무 효과도 없다.
                  // 버튼 사이를 벌리려면 width 를 줘야 한다.
                  const SizedBox(height: 10),
                  // 얼굴 등록 버튼.
                  // ⚠️ onPressed 가 비어 있어 **아무 동작도 하지 않는다.**
                  //    실습: 여기에 `setState(() => register = true);` 를 넣으면
                  //    다음 프레임에서 얼굴을 잘라 등록 절차가 시작되도록 만들 수 있다.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: IconButton(
                      icon: Icon(
                        Icons.face_retouching_natural,
                        color: Colors.white,
                      ),
                      iconSize: 40,
                      color: Colors.black,
                      onPressed: () {},
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

/// 검출된 얼굴 위에 사각형을 직접 그리는 클래스.
///
/// `CustomPainter` 는 위젯을 조합하는 대신 캔버스에 선/도형/글자를 **직접 그릴 때**
/// 사용한다. 얼굴 위치가 매 프레임 달라지므로 위젯보다 이 방식이 적합하다.
///
/// ⚠️ 현재 이 화면에서는 아직 사용되지 않는다 (buildResult() 가 주석 처리됨).
///
/// 참고: 이름은 같지만 인식 화면(recognition_screen.dart)의 FaceDetectorPainter 와는
/// **다른 클래스**다. 이쪽은 ML Kit의 `Face` 를 받아 사각형만 그리고,
/// 저쪽은 `Recognition` 을 받아 이름표까지 그린다.
class FaceDetectorPainter extends CustomPainter {
  /// 카메라 원본 이미지의 크기. 좌표 변환의 기준이 된다.
  final Size absoluteImageSize;

  /// ML Kit이 검출한 얼굴 목록.
  final List<Face> faces;

  /// 전면/후면 여부. 전면이면 좌우를 뒤집어 그려야 한다.
  final CameraLensDirection camDirection;

  FaceDetectorPainter(this.absoluteImageSize, this.faces, this.camDirection);

  /// 실제로 그리는 함수. Flutter가 필요할 때 호출한다.
  /// [size] 는 그림을 그릴 화면 영역의 크기다.
  @override
  void paint(Canvas canvas, Size size) {
    // 원본 이미지 좌표 → 화면 좌표로 바꾸기 위한 배율.
    // 예: 원본 640px 폭이 화면 390px 라면 scaleX = 0.609
    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;

    // Paint: 붓 설정. stroke 는 테두리만, fill 은 안을 채운다.
    // `..` 은 cascade 문법으로, 같은 객체에 설정을 연달아 적용한다.
    final Paint boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.deepPurple.shade300;

    // 이름표 배경용 붓. (이 화면에서는 이름표를 그리지 않아 아직 쓰이지 않는다)
    final Paint labelBgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.deepPurple.shade300.withAlpha(150);

    for (final face in faces) {
      // 전면 카메라는 거울처럼 좌우가 반전되어 보이므로
      // (전체 너비 - 오른쪽) 을 왼쪽으로 삼아 x 좌표를 뒤집는다.
      final double left = camDirection == CameraLensDirection.front
          ? (absoluteImageSize.width - face.boundingBox.right) * scaleX
          : face.boundingBox.left * scaleX;
      // 위아래는 뒤집을 필요가 없다.
      final double top = face.boundingBox.top * scaleY;
      final double right = camDirection == CameraLensDirection.front
          ? (absoluteImageSize.width - face.boundingBox.left) * scaleX
          : face.boundingBox.right * scaleX;
      final double bottom = face.boundingBox.bottom * scaleY;

      // 모서리가 둥근 사각형을 그린다.
      final rect = Rect.fromLTRB(left, top, right, bottom);
      final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(rRect, boxPaint);
    }
  }

  /// 다시 그릴지 여부. 매 프레임 얼굴 위치가 바뀌므로 항상 true 다.
  ///
  /// (성능을 더 챙기려면 얼굴 목록이 실제로 바뀌었을 때만 true 를 돌려주면 된다)
  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) => true;
}
