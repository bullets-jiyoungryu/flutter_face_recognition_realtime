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
/// **전체 흐름 (한 장의 프레임이 거치는 길)**
/// ```
/// 카메라 스트림 → startImageStream 콜백 (isBusy 로 프레임 솎아내기)
///   → doFaceDetectionOnFrame()   프레임을 InputImage 로 변환
///   → faceDetector.processImage() ML Kit이 "얼굴이 어디 있는지" 알려줌
///   → performFaceRecognition()   변환·회전·크롭 → recognizer 로 임베딩 추출
///   → showFaceRegistrationDialogue()  이름을 입력받아 DB에 저장
/// ```
///
/// **여기서 ML Kit과 FaceNet의 역할이 다르다는 점이 핵심이다.**
/// - ML Kit(`google_mlkit_face_detection`): "사진 어디에 얼굴이 있는가" (**위치**)
/// - FaceNet(`ml/recognizer.dart`): "그 얼굴이 누구인가" (**정체**)
///
/// 이 화면은 `recognition_screen.dart` 와 구조가 거의 같지만,
/// **사용자가 등록 버튼을 눌렀을 때만**(`register` 깃발) 얼굴을 처리한다는 점이 다르다.
///
/// 소스 곳곳의 `//TODO` 주석은 원래 강의용 실습 표시였고,
/// 지금은 **이미 구현이 끝난 상태**다. 각 단계를 찾아가는 이정표로 읽으면 된다.
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

  /// 인식 결과 목록.
  ///
  /// 참고: 등록 화면에서는 `performFaceRecognition()` 이 시작할 때
  /// `clear()` 만 하고 결과를 담지는 않으므로 **항상 비어 있다.**
  /// (인식 화면에서 복사해 오면서 남은 필드다. 화면에 이름표를 그리지 않는
  ///  등록 화면에서는 없어도 되는 값이다)
  late List<Recognition> recognitions = [];

  //TODO declare face detector
  /// ML Kit 얼굴 **검출기**. 사진 속 얼굴의 위치(사각형)를 찾아준다.
  /// 누구인지는 알려주지 않는다 — 그건 아래 [recognizer] 의 몫이다.
  late FaceDetector faceDetector;

  //TODO declare face recognizer
  /// FaceNet 얼굴 **인식기**. 잘라낸 얼굴에서 512차원 임베딩을 뽑고
  /// DB 저장/조회까지 담당한다. (`ml/recognizer.dart`)
  late Recognizer recognizer;

  /// 화면이 처음 만들어질 때 한 번 호출된다.
  ///
  /// 무거운 객체(검출기·모델·카메라)를 여기서 딱 한 번 만들어 둔다.
  /// build() 안에서 만들면 화면을 다시 그릴 때마다 새로 만들어져 버린다.
  @override
  void initState() {
    // 부모 클래스의 초기화를 먼저 끝내는 것이 규칙이다. 항상 맨 위에 둔다.
    super.initState();

    //TODO initialize face detector
    // FaceDetectorOptions 로 검출기의 동작을 정한다.
    // - performanceMode: fast  → 빠르지만 정확도는 조금 낮다(실시간 영상에 적합)
    //                    accurate → 느리지만 정확하다(사진 한 장 처리에 적합)
    // 이 밖에 자주 쓰는 옵션:
    // - enableLandmarks: 눈·코·입 위치까지 얻기
    // - enableContours : 얼굴 윤곽선 점들 얻기
    // - enableClassification: 웃고 있는지 / 눈을 떴는지 확률로 얻기
    //   (라이브니스를 눈 깜빡임으로 구현하려면 이 옵션이 필요하다)
    // - minFaceSize    : 프레임 대비 이 비율보다 작은 얼굴은 무시
    // 옵션을 켤수록 느려지므로 필요한 것만 켠다.
    FaceDetectorOptions options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
    );
    faceDetector = FaceDetector(options: options);

    //TODO initialize face recognizer
    // ⚠️ 생성자가 TFLite 모델 로딩을 기다리지 않는다(`ml/recognizer.dart` 참고).
    // 카메라가 준비되고 첫 프레임이 오기까지 시간이 걸려서 대체로 문제가 없지만,
    // 엄밀히는 "운 좋게 동작하는" 코드다.
    recognizer = Recognizer();

    //TODO initialize camera footage
    // 카메라 켜기. async 함수지만 initState 는 await 할 수 없으므로
    // 호출만 해두고, 준비가 끝나면 그 안에서 setState 로 화면을 갱신한다.
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
  /// ML Kit 검출기와 TFLite 인터프리터도 네이티브 자원을 잡고 있으므로
  /// 함께 닫아야 한다. 닫지 않으면 화면을 드나들 때마다 쌓여서
  /// 메모리가 계속 늘어난다. 특히 facenet.tflite 는 23MB 라 부담이 크다.
  @override
  void dispose() {
    controller?.dispose();
    faceDetector.close();
    recognizer.close();
    // super.dispose() 는 항상 **마지막에** 호출하는 것이 규칙이다.
    super.dispose();
  }

  //TODO face detection on a frame
  /// 화면에 사각형을 그릴 때 쓰는 검출 결과.
  ///
  /// 등록 화면에서는 ML Kit의 `List<Face>` 가 그대로 들어간다.
  /// (인식 화면에서는 같은 이름의 변수에 `List<Recognition>` 이 들어간다 —
  ///  타입이 `dynamic` 이라 이런 차이가 컴파일 시점에 드러나지 않는다)
  dynamic _scanResults;

  /// 가장 최근에 카메라에서 받은 프레임 한 장.
  ///
  /// 스트림 콜백이 여기에 덮어쓰고, 아래 함수들이 꺼내 쓴다.
  /// `isBusy` 덕분에 "쓰는 중에 덮어쓰이는" 일이 없다.
  CameraImage? frame;

  /// 프레임 한 장에서 얼굴을 찾아낸다. **파이프라인의 1단계다.**
  ///
  /// 이 함수는 `initializeCamera()` 의 스트림 콜백에서 프레임마다 호출된다.
  ///
  /// ⚠️ 어떤 경로로 함수가 끝나든 반드시 `isBusy = false` 가 되어야 한다.
  /// 중간에 return 하는 분기를 만들었다면 거기서도 꼭 되돌려 놓자.
  /// 안 그러면 이후 모든 프레임이 무시되어 화면이 멈춘 것처럼 보인다.
  doFaceDetectionOnFrame() async {
    //TODO convert frame into InputImage format
    // ① 카메라 프레임을 ML Kit이 이해하는 형식으로 변환한다.
    InputImage? inputImage = getInputImage();
    // 변환 실패(포맷/회전 문제)면 이번 프레임은 건너뛴다.
    // 이때 isBusy 를 내려주지 않으면 스트림이 영구히 멈추므로 꼭 필요한 코드다.
    if (inputImage == null) {
      setState(() {
        isBusy = false;
      });
      return;
    }

    //TODO pass InputImage to face detection model and detect faces
    // ② ML Kit에 넘겨 얼굴을 검출한다. 네이티브(Android/iOS) 쪽에서 도는
    //    작업이라 시간이 걸리므로 await 로 결과를 기다린다.
    //    얼굴이 없으면 빈 리스트가 돌아온다(예외가 아니다).
    List<Face> faces = await faceDetector.processImage(inputImage);
    // 참고: Dart에서 문자열을 이을 때는 `+` 보다 `'faces=${faces.length}'`
    // 같은 문자열 보간이 관례다.
    print('faces=' + faces.length.toString());

    //TODO perform face recognition on detected faces
    // ③ 검출된 얼굴들을 잘라내어 임베딩 추출/등록 단계로 넘긴다.
    //    (await 를 붙이지 않아 이 함수는 여기서 바로 끝난다.
    //     대신 isBusy 정리를 performFaceRecognition() 이 맡는다)
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
  // performFaceRecognition() 이 하는 일:
  //   ① 카메라 프레임을 img.Image 로 변환 (OS별로 다른 함수 사용)
  //   ② 세로 방향이 되도록 회전 (전면 270도 / 후면 90도)
  //   ③ 검출된 얼굴 사각형대로 잘라내기(crop)
  //   ④ 잘라낸 얼굴을 recognizer 에 넣어 임베딩 추출
  //   ⑤ 이름 입력 다이얼로그 띄우기
  // ─────────────────────────────────────────────────────────────

  /// 이번 프레임을 이미지로 변환·회전한 결과. 여기서 얼굴을 잘라낸다.
  img.Image? image;

  /// **등록 예약 깃발.**
  ///
  /// 하단 얼굴 버튼을 누르면 `true` 가 되고, 다음 프레임이 들어왔을 때
  /// 아래 `if (register)` 블록이 한 번 실행된 뒤 다시 `false` 로 돌아간다.
  ///
  /// 버튼을 누른 그 순간 바로 처리하지 않는 이유는, 버튼 콜백에는
  /// "지금 이 순간의 프레임"이 없기 때문이다. 카메라 스트림이 다음 장을
  /// 가져다줄 때까지 기다렸다가 그 프레임으로 등록한다.
  bool register = false;

  //TODO perform Face Recognition
  /// 검출된 얼굴들을 잘라내고, 등록이 예약돼 있으면 임베딩까지 뽑는다.
  /// **파이프라인의 2단계다.**
  performFaceRecognition(List<Face> faces) async {
    // 지난 프레임의 결과를 비운다.
    // (등록 화면에서는 이 목록을 채우지 않으므로 사실상 하는 일이 없다)
    recognitions.clear();

    //TODO convert CameraImage to Image and rotate it so that our frame will be in a portrait
    // ① 카메라 프레임(CameraImage)을 픽셀을 다룰 수 있는 img.Image 로 바꾼다.
    //    OS마다 프레임 포맷이 달라서 변환 함수도 다르다(`util.dart` 참고).
    //      - iOS    : BGRA8888
    //      - Android: NV21
    image = Platform.isIOS
        ? Util.convertBGRA8888ToImage(frame!)
        : Util.convertNV21(frame!);
    // ② 세로(초상) 방향으로 회전시킨다.
    //    카메라 센서는 가로로 누워 있어서, 변환 직후 이미지는 90도 돌아가 있다.
    //    이 보정을 빼먹으면 얼굴이 옆으로 누운 채로 모델에 들어가 인식률이 급락한다.
    //    전면은 270도, 후면은 90도인 이유는 두 센서의 장착 방향이 반대이기 때문이다.
    image = img.copyRotate(
      image!,
      angle: camDirec == CameraLensDirection.front ? 270 : 90,
    );

    // 등록 버튼을 누른 직후의 프레임에서만 아래 블록이 실행된다.
    // 평소에는 건너뛰므로, 등록 화면은 얼굴 위치만 계속 그린다.
    if (register) {
      // 화면에 얼굴이 여럿이면 사람 수만큼 반복된다.
      // ⚠️ 그 경우 등록 다이얼로그도 얼굴 수만큼 겹쳐 뜬다.
      //    한 명만 등록하고 싶다면 `faces.isNotEmpty` 일 때 첫 얼굴만 쓰거나,
      //    얼굴이 2개 이상이면 안내 문구를 띄우는 편이 좋다.
      for (Face face in faces) {
        // ML Kit이 알려준 얼굴 사각형. 원본 이미지 좌표 기준이다.
        Rect faceRect = face.boundingBox;

        //TODO crop face
        // ③ 얼굴 부분만 잘라낸다. double 좌표를 toInt() 로 정수로 바꿔 넘긴다.
        //
        // ⚠️ 얼굴이 화면 가장자리에 걸치면 boundingBox 가 이미지 밖으로
        //    삐져나가 크롭에서 예외가 날 수 있다. 실제 앱에서는
        //    `clamp()` 로 좌표를 이미지 범위 안에 가두는 방어 코드를 넣는 게 좋다.
        img.Image croppedFace = img.copyCrop(
          image!,
          x: faceRect.left.toInt(),
          y: faceRect.top.toInt(),
          width: faceRect.width.toInt(),
          height: faceRect.height.toInt(),
        );

        //TODO pass cropped face to face recognition model
        // ④ 잘라낸 얼굴을 FaceNet에 넣어 임베딩(숫자 512개)을 뽑는다.
        //    내부에서 160x160 리사이즈와 정규화까지 알아서 처리한다.
        //
        // 참고: recognize() 는 Future 가 아니라 Recognition 을 바로 반환한다.
        //      여기 붙은 await 는 없어도 되지만, 있어도 문제는 없다.
        //      (반환된 recognition.name/distance 는 "이미 등록된 사람인지"를
        //       알려준다. 중복 등록을 막고 싶다면 이 값으로 걸러낼 수 있다)
        Recognition recognition = await recognizer.recognize(
          croppedFace,
          faceRect,
        );

        //TODO show face registration dialogue
        // ⑤ 이름을 입력받아 저장하는 창을 띄운다.
        //    await 하지 않으므로 창이 뜬 채로 반복문은 계속 진행된다.
        showFaceRegistrationDialogue(croppedFace, recognition);
      }

      // 한 번 처리했으니 예약을 해제한다.
      // 이걸 빼먹으면 프레임마다 다이얼로그가 무한히 쌓인다.
      register = false;
    }

    // 이번 프레임 처리 완료. isBusy 를 내려 다음 프레임을 받을 준비를 하고,
    // 검출 결과를 화면(사각형)에 반영한다.
    setState(() {
      isBusy = false;
      _scanResults = faces;
    });
  }

  //TODO Face Registration Dialogue
  /// 이름 입력칸의 글자를 읽어오기 위한 컨트롤러.
  ///
  /// `TextField` 에 사용자가 친 글자는 이 객체의 `.text` 로 꺼낸다.
  ///
  /// ⚠️ 원칙적으로는 `dispose()` 에서 `textEditingController.dispose()` 를
  ///    호출해 정리해야 한다. 지금은 빠져 있다.
  /// ⚠️ 화면 전체가 하나의 컨트롤러를 공유하므로, 연속으로 등록하면
  ///    이전에 입력한 이름이 그대로 남아 있다. 저장 후 `.clear()` 를
  ///    불러주면 깔끔하다.
  TextEditingController textEditingController = TextEditingController();

  /// 잘라낸 얼굴 사진을 보여주고 이름을 입력받아 DB에 저장하는 다이얼로그.
  ///
  /// [croppedFace] 미리보기로 보여줄(그리고 DB에 함께 저장할) 얼굴 이미지
  /// [recognition] 방금 추출한 임베딩이 들어 있는 인식 결과
  showFaceRegistrationDialogue(img.Image croppedFace, Recognition recognition) {
    // showDialog: 화면 위에 떠 있는 창을 띄운다.
    // builder 가 창의 내용을 만들어 준다. (여기서 받은 `ctx` 는 아래에서
    // 쓰이지 않고, 대신 State 의 `context` 를 쓰고 있다 — 지금 구조에서는
    // 문제없이 동작하지만 보통은 `ctx` 를 쓰는 편이 안전하다)
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        // 배경을 투명으로 두어야 아래 BackdropFilter 의 유리 효과가 살아난다.
        backgroundColor: Colors.transparent,
        // insetPadding: 창과 화면 가장자리 사이의 여백. 창의 최대 크기를 정한다.
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        // ClipRRect 로 모서리를 둥글게 잘라야 흐림 효과가 사각형 밖으로 새지 않는다.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            // 창 뒤에 비치는 카메라 화면을 뿌옇게 흐린다.
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                // withAlpha(30): 거의 투명한 흰색을 얹어 유리 느낌을 낸다(0~255).
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withAlpha(40)),
              ),
              // SingleChildScrollView: 키보드가 올라와 공간이 좁아졌을 때
              // 내용이 넘쳐 깨지지 않도록 스크롤할 수 있게 감싼다.
              child: SingleChildScrollView(
                child: Column(
                  // 세로로 꽉 채우지 말고 내용만큼만 차지하라는 뜻.
                  // 다이얼로그에서는 거의 항상 필요하다.
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Register Your Face",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── 잘라낸 얼굴 미리보기 (원형) ──
                    // borderRadius 를 크게 주면 정사각형이 원처럼 잘린다.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      // img.Image 는 Flutter 위젯이 바로 그릴 수 없으므로
                      // encodeBmp() 로 이미지 파일 형식의 바이트로 바꾼 뒤
                      // Image.memory() 로 그린다.
                      // (BMP는 압축이 없어 인코딩이 빠르다. 화면에 잠깐 보여줄
                      //  용도라 용량은 문제되지 않는다)
                      child: Image.memory(
                        Uint8List.fromList(img.encodeBmp(croppedFace)),
                        width: 150,
                        height: 150,
                        // BoxFit.cover: 비율을 유지한 채 영역을 꽉 채운다(넘치면 잘림).
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── 이름 입력칸 ──
                    TextField(
                      // 위에서 만든 컨트롤러를 연결해야 `.text` 로 값을 읽을 수 있다.
                      controller: textEditingController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Enter your name",
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withAlpha(80),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── 저장 버튼 ──
                    // SizedBox(width: double.infinity) 로 감싸면 버튼이 가로로 꽉 찬다.
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // 이름 + 임베딩 + 얼굴 사진을 DB에 저장한다.
                          //
                          // ⚠️ registerFaceInDB 는 `void ... async` 라 await 할 수 없다.
                          //    즉 저장이 끝나기 전에 아래 화면 닫기가 먼저 실행된다.
                          //    (실제로는 금방 끝나서 문제가 드러나지 않는다)
                          // ⚠️ 이름이 비어 있어도 그대로 저장된다.
                          //    `.trim().isEmpty` 검사를 넣어 막는 것이 좋다.
                          // ⚠️ 저장 후 recognizer.registered 캐시를 갱신하지 않으므로,
                          //    방금 등록한 얼굴은 앱을 다시 켜야 인식된다.
                          //    (`ml/recognizer.dart` 의 registerFaceInDB 설명 참고)
                          recognizer.registerFaceInDB(
                            textEditingController.text.trim(),
                            recognition.embeddings,
                            // croppedFace 는 null 이 될 수 없으므로 `!` 는 불필요하다.
                            Uint8List.fromList(img.encodeBmp(croppedFace!)),
                          );
                          // pop 이 두 번인 이유:
                          //   1번째 → 이 다이얼로그를 닫는다
                          //   2번째 → 등록 화면 자체를 닫고 홈으로 돌아간다
                          // (등록 후 카메라 화면에 계속 머물고 싶다면 두 번째 pop 을 지운다)
                          Navigator.pop(context);
                          Navigator.pop(context); // Close dialog
                          // 화면 아래에 잠깐 떴다 사라지는 알림 띠를 보여준다.
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Face Registered")),
                          );
                        },
                        icon: const Icon(Icons.check),
                        label: const Text("Register"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
  /// 검출된 얼굴 위에 사각형을 그리는 레이어를 만든다.
  ///
  /// build() 의 Stack 에서 카메라 프리뷰 위에 얹어 사용한다.
  Widget buildResult() {
    // 아직 검출 결과가 없거나 카메라가 준비되지 않았으면 안내 문구만 보여준다.
    // (카메라 프리뷰 위에 겹쳐 있어서 실제로는 이 글자가 프리뷰 위에 떠 보인다)
    if (_scanResults == null ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(child: Text('Camera is not initialized'));
    }
    // ⚠️ previewSize 의 height 를 width 자리에, width 를 height 자리에
    //    **바꿔서** 넣는다. 카메라 프레임이 가로로 누운 상태로 오기 때문이다.
    //    사각형 위치가 어긋난다면 여기를 가장 먼저 의심하자.
    final Size imageSize = Size(
      controller.value.previewSize!.height,
      controller.value.previewSize!.width,
    );
    // 아래에 정의된 CustomPainter 에 그릴 재료를 넘긴다.
    CustomPainter painter = FaceDetectorPainter(
      imageSize,
      _scanResults,
      camDirec,
    );
    // CustomPaint: painter 가 그린 그림을 화면에 얹는 위젯.
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
                  //
                  // 이 버튼은 등록을 "예약"만 한다. 여기서 바로 얼굴을 자르지 않고
                  // register 깃발만 세워두면, 다음 카메라 프레임이 들어왔을 때
                  // performFaceRecognition() 의 `if (register)` 블록이 실행되어
                  // 크롭 → 임베딩 추출 → 이름 입력 다이얼로그로 이어진다.
                  //
                  // setState 로 감쌀 필요는 없다. register 는 build() 안에서
                  // 읽지 않으므로 화면을 다시 그릴 이유가 없기 때문이다.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: IconButton(
                      icon: Icon(
                        Icons.face_retouching_natural,
                        color: Colors.white,
                      ),
                      iconSize: 40,
                      color: Colors.black,
                      onPressed: () {
                        register = true;
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

/// 검출된 얼굴 위에 사각형을 직접 그리는 클래스.
///
/// `CustomPainter` 는 위젯을 조합하는 대신 캔버스에 선/도형/글자를 **직접 그릴 때**
/// 사용한다. 얼굴 위치가 매 프레임 달라지므로 위젯보다 이 방식이 적합하다.
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

    // 이름표 배경용 붓.
    // ⚠️ 등록 화면은 사각형만 그리고 이름표는 그리지 않으므로 실제로 쓰이지 않는다.
    //    (인식 화면의 같은 이름 클래스에서는 이 붓으로 이름표 배경을 칠한다)
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
