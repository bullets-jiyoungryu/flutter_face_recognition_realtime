// sqrt() (제곱근) 함수를 쓰기 위해 필요하다. 코사인 유사도 계산에 사용된다.
import 'dart:math';

// Uint8List(바이트 배열), Float32List(32비트 실수 배열) 같은 고정 타입 배열.
import 'dart:typed_data';

// Rect(사각형) 타입.
import 'dart:ui';

// image 패키지: 이미지 리사이즈/자르기/인코딩 등 순수 Dart 이미지 처리.
// `as img` 는 "이 패키지의 것들은 img. 을 붙여서 쓰겠다"는 별칭 지정이다.
// (Flutter 기본 Image 위젯과 이름이 겹치는 것을 피하기 위함)
import 'package:image/image.dart' as img;

// tflite_flutter 패키지: TensorFlow Lite 모델을 기기에서 직접 실행한다.
import 'package:tflite_flutter/tflite_flutter.dart';
import '../db/database_helper.dart';
import 'recognition.dart';

/// 얼굴 인식의 **핵심 엔진**.
///
/// 하는 일은 크게 세 가지다.
/// 1. TFLite 모델(FaceNet)을 메모리에 올린다.
/// 2. 얼굴 이미지를 넣으면 512개 숫자로 된 특징 벡터(임베딩)를 뽑아낸다.
/// 3. 그 벡터를 DB에 저장된 얼굴들과 비교해 가장 닮은 사람을 찾는다.
///
/// ⚠️ **초심자가 가장 많이 걸려 넘어지는 지점**
/// 생성자가 `loadModel()` 과 `initDB()` 를 `await` 없이 호출한다.
/// 즉 `Recognizer()` 로 객체를 만든 직후에는 모델이 아직 로딩 중일 수 있고,
/// 바로 `recognize()` 를 부르면 `interpreter` 가 준비되지 않아
/// `LateInitializationError` 가 발생한다.
/// 화면에서 사용할 때는 잠깐의 준비 시간을 고려하도록 만들어야 한다.
class Recognizer {
  /// TFLite 모델을 실행하는 객체. loadModel() 이 끝나야 사용할 수 있다.
  late Interpreter interpreter;

  /// 모델 실행 옵션(스레드 수 등)을 담는 객체.
  ///
  /// 참고: 아래 생성자에서 값을 설정하기는 하지만, 현재
  /// `Interpreter.fromAsset()` 에 전달하지 않아 **실제로는 적용되지 않는다.**
  /// 적용하려면 `Interpreter.fromAsset(modelName, options: _interpreterOptions)`
  /// 처럼 넘겨야 한다.
  late InterpreterOptions _interpreterOptions;

  /// 모델이 요구하는 입력 이미지 가로 크기(픽셀).
  static const int WIDTH = 160;

  /// 모델이 요구하는 입력 이미지 세로 크기(픽셀).
  static const int HEIGHT = 160;

  /// 모델이 뱉어내는 특징 벡터의 길이.
  ///
  /// 💡 모델을 바꾸려면 아래 `modelName` 과 이 세 상수(WIDTH/HEIGHT/OUTPUT)를
  ///    **반드시 함께** 맞춰야 한다. 예를 들어 assets 폴더에 같이 들어 있는
  ///    `mobile_face_net.tflite` 는 입력 크기와 출력 차원이 달라서
  ///    파일 이름만 바꾸면 동작하지 않는다.
  static const int OUTPUT = 512;

  /// DB 접근 도우미. 이 클래스 전용 인스턴스다.
  final dbHelper = DatabaseHelper();

  /// DB에서 불러온 등록 얼굴들을 담아두는 **메모리 캐시**.
  ///
  /// 매번 DB를 읽으면 느리기 때문에 앱 시작 시 한 번 읽어 여기에 올려둔다.
  /// 키는 **사람 이름**이다.
  ///
  /// ⚠️ 이름이 키이므로 같은 이름으로 두 번 등록하면 DB에는 행이 2개 생기지만
  /// 이 캐시에는 (아래 putIfAbsent 때문에) 먼저 넣은 것 하나만 남는다.
  ///
  /// (`Map()` 대신 요즘 Dart 스타일인 `{}` 로 써도 완전히 같다)
  Map<String, Recognition> registered = Map();

  /// 사용할 모델 파일 경로. pubspec.yaml 의 assets 에 등록되어 있어야 한다.
  ///
  /// (참고: 여기 붙은 `@override` 는 상속받은 것이 없어 실제로는 의미가 없다.
  ///  `flutter analyze` 가 경고를 내는 부분이며, 지워도 동작에는 영향이 없다.)
  @override
  String get modelName => 'assets/facenet.tflite';

  /// 생성자. [numThreads] 로 모델 실행에 쓸 스레드 수를 지정할 수 있다.
  ///
  /// 위 클래스 설명에서 언급했듯 loadModel()/initDB() 를 기다리지 않는다.
  Recognizer({int? numThreads}) {
    _interpreterOptions = InterpreterOptions();

    if (numThreads != null) {
      _interpreterOptions.threads = numThreads;
    }
    loadModel();
    initDB();
  }

  /// DB를 열고 등록된 얼굴들을 메모리로 불러온다.
  ///
  /// 반환 타입을 적지 않아 `dynamic` 으로 추론되지만, `async` 함수이므로
  /// 실제로는 `Future` 를 돌려준다. `Future<void>` 로 명시하는 편이 낫다.
  initDB() async {
    // DB 파일을 열고 테이블이 없으면 만든다. 이게 끝나야 조회가 가능하므로 await.
    await dbHelper.init();
    // ⚠️ 여기는 await 를 붙이지 않았다(아래 함수가 void 반환이라 붙일 수도 없다).
    // 즉 initDB() 가 끝나도 캐시 로딩은 아직 진행 중일 수 있다.
    loadRegisteredFaces();
  }

  /// DB에 저장된 모든 얼굴을 읽어 [registered] 캐시에 채운다.
  ///
  /// ⚠️ `void` + `async` 조합이라 **완료를 기다릴 수 없다**(fire-and-forget).
  /// 호출한 쪽에서 "다 불러왔는지" 알 방법이 없고, 내부에서 예외가 나도
  /// 아무도 잡지 못한다. `Future<void>` 로 바꾸면 await 할 수 있다.
  void loadRegisteredFaces() async {
    final allRows = await dbHelper.queryAllRows();
    // debugPrint('query all rows:');
    for (final row in allRows) {
      //  debugPrint(row.toString());
      print(row[DatabaseHelper.columnName]);
      String name = row[DatabaseHelper.columnName];

      // DB에는 "0.12,-0.98,..." 형태의 문자열로 저장되어 있으므로
      // 콤마로 쪼갠 뒤 각 조각을 실수로 변환해 List<double> 로 되돌린다.
      List<double> embd = row[DatabaseHelper.columnEmbedding]
          .split(',')
          .map((e) => double.parse(e))
          .toList()
          .cast<double>();

      // 캐시에 넣을 때는 화면 위치(location)와 유사도(distance)가 의미 없으므로
      // 각각 Rect.zero 와 0 을 넣어둔다.
      Recognition recognition = Recognition(
        row[DatabaseHelper.columnName],
        Rect.zero,
        embd,
        0,
      );

      // putIfAbsent: 해당 키가 아직 없을 때만 넣는다 (있으면 무시).
      registered.putIfAbsent(name, () => recognition);
    }
  }

  /// 얼굴 사진을 DB에 넣기 좋은 크기로 줄이고 JPEG으로 압축한다.
  ///
  /// [maxSizeInKB] 이하가 될 때까지 품질을 낮춰가며 반복한다.
  Future<Uint8List> compressImage(
    Uint8List imageData, {
    int maxSizeInKB = 500,
  }) async {
    // 바이트 배열을 다룰 수 있는 이미지 객체로 해석한다.
    img.Image? image = img.decodeImage(imageData);
    if (image == null) throw Exception('Image decoding failed');

    // Resize to smaller dimensions if necessary
    // 가로 300px 로 축소한다. 높이는 비율에 맞춰 자동 계산된다.
    img.Image resized = img.copyResize(image, width: 300); // ~300px width

    int quality = 85; // Start with high quality
    Uint8List jpg;

    // 품질을 5씩 낮추면서 목표 용량 이하가 될 때까지 반복한다.
    // 품질이 20 이하로 떨어지면 더 낮추지 않고 멈춘다(화질 하한선).
    do {
      jpg = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      quality -= 5;
    } while (jpg.lengthInBytes > maxSizeInKB * 1024 && quality > 20);

    return jpg;
  }

  /// 새 얼굴을 DB에 등록한다.
  ///
  /// [name] 사람 이름, [embedding] 특징 벡터, [faceImage] 잘라낸 얼굴 사진 바이트.
  ///
  /// ⚠️ 여기서는 DB에만 넣고 [registered] 캐시는 갱신하지 않는다.
  /// 그래서 등록 직후 바로 인식하면 못 알아볼 수 있다.
  /// 등록 후 `loadRegisteredFaces()` 를 다시 부르거나
  /// 캐시에 직접 추가하는 코드를 넣어주면 좋다.
  void registerFaceInDB(
    String name,
    List<double> embedding,
    Uint8List faceImage,
  ) async {
    Uint8List compressedImage = await compressImage(faceImage);
    Map<String, dynamic> row = {
      DatabaseHelper.columnName: name,
      // List<double> 을 "0.12,-0.98,..." 형태의 한 줄 문자열로 만든다.
      DatabaseHelper.columnEmbedding: embedding.join(","),
      'image': compressedImage,
    };
    final id = await dbHelper.insert(row);
    print('inserted row id: $id');
  }

  // 아래는 이미지 없이 이름+임베딩만 저장하던 예전 버전이다.
  // ⚠️ 되살려 쓰면 안 된다. 테이블의 image 컬럼이 NOT NULL 이라 insert 가 실패한다.
  // void registerFaceInDB(String name, List<double> embedding) async {
  //   // row to insert
  //   Map<String, dynamic> row = {
  //     DatabaseHelper.columnName: name,
  //     DatabaseHelper.columnEmbedding: embedding.join(",")
  //   };
  //   final id = await dbHelper.insert(row);
  //   print('inserted row id: $id');
  // }

  /// assets 폴더의 TFLite 모델 파일을 읽어 실행 준비를 한다.
  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(modelName);
    } catch (e) {
      // ⚠️ 여기서 예외를 잡아 로그만 찍고 넘어가기 때문에,
      // 모델 로딩에 실패해도 앱은 계속 실행된다.
      // 대신 나중에 recognize() 를 부를 때 LateInitializationError 로 터진다.
      // 실제 앱에서는 로딩 성공 여부를 bool 로 들고 있다가 UI에 알려주는 편이 좋다.
      print('Unable to create interpreter, Caught Exception: ${e.toString()}');
    }
  }

  /// 이미지를 모델이 먹을 수 있는 숫자 배열로 바꾼다.
  ///
  /// 결과 모양(shape)은 `[1, 160, 160, 3]` 이다.
  /// 각 숫자의 뜻: [한 번에 처리할 장수, 세로, 가로, 색상채널(RGB)]
  List<dynamic> imageToArray(img.Image inputImage) {
    // 모델이 요구하는 160x160 크기로 강제 변환한다.
    // (`inputImage!` 의 `!` 는 이미 null 이 아닌 값이라 사실 불필요하다.
    //  analyze 가 경고하는 부분이며 지워도 동작은 같다)
    img.Image resizedImage = img.copyResize(
      inputImage!,
      width: WIDTH,
      height: HEIGHT,
    );

    // 픽셀들을 R,G,B,R,G,B,... 순서의 1차원 실수 목록으로 펼친다.
    List<double> flattenedList = resizedImage.data!
        .expand((channel) => [channel.r, channel.g, channel.b])
        .map((value) => value.toDouble())
        .toList();
    Float32List float32Array = Float32List.fromList(flattenedList);

    int channels = 3;
    int height = HEIGHT;
    int width = WIDTH;
    Float32List reshapedArray = Float32List(1 * height * width * channels);

    // 아래 3중 반복문이 하는 일은 결국 **정규화** 하나뿐이다.
    // 0~255 범위의 픽셀 값을 -1.0~1.0 범위로 바꾼다: (x - 127.5) / 127.5
    //
    // 참고: 좌변 index 와 우변에서 읽는 위치가 완전히 같은 식이라
    // 순서를 바꾸는 효과는 없고 사실상 "그대로 복사 + 정규화" 다.
    // (원래는 채널 순서를 바꾸려던 코드로 보이지만 현재는 그렇게 동작하지 않는다)
    for (int c = 0; c < channels; c++) {
      for (int h = 0; h < height; h++) {
        for (int w = 0; w < width; w++) {
          int index = c * height * width + h * width + w;
          reshapedArray[index] =
              (float32Array[c * height * width + h * width + w] - 127.5) /
              127.5;
        }
      }
    }

    // 1차원 배열을 모델 입력 모양인 4차원으로 재구성한다.
    // `reshape()` 는 Dart 기본 기능이 아니라 tflite_flutter 가 List 에 붙여준
    // 확장(extension) 메서드다. 이 패키지를 import 해야만 쓸 수 있다.
    return reshapedArray.reshape([1, WIDTH, HEIGHT, 3]);
  }

  /// 얼굴 이미지 한 장을 인식한다.
  ///
  /// [image] 는 이미 얼굴 부분만 잘라낸 이미지여야 하고,
  /// [location] 은 화면에 사각형을 그릴 때 쓸 원본 이미지 기준 위치다.
  ///
  /// 반환값의 `name` 은 가장 닮은 사람 이름, `distance` 는 그 유사도다.
  Recognition recognize(img.Image image, Rect location) {
    //TODO crop face from image resize it and convert it to float array
    // 이미지를 모델 입력 형태([1,160,160,3])로 변환한다.
    var input = imageToArray(image);
    // `shape` 도 tflite_flutter 의 확장 게터로, 중첩 List 의 모양을 알려준다.
    // 여기서는 "[1, 160, 160, 3]" 이 찍혀야 정상이다.
    print(input.shape.toString());

    //TODO output array
    // 결과를 받을 빈 배열을 미리 만들어 둔다. TFLite는 이 배열을 채워준다.
    List output = List.filled(1 * OUTPUT, 0).reshape([1, OUTPUT]);

    //TODO performs inference
    // 추론 실행. 걸린 시간을 밀리초로 측정해 로그로 남긴다.
    final runs = DateTime.now().millisecondsSinceEpoch;
    interpreter.run(input, output);
    final run = DateTime.now().millisecondsSinceEpoch - runs;
    print('Time to run inference: $run ms$output');

    //TODO convert dynamic list to double list
    // output 은 List<dynamic> 이므로 다루기 쉽게 List<double> 로 변환한다.
    List<double> outputArray = output.first.cast<double>();

    //TODO looks for the nearest embeeding in the database and returns the pair
    // 등록된 얼굴 중 가장 닮은 사람을 찾는다.
    Pair pair = findNearest(outputArray);
    print("distance= ${pair.distance}");

    return Recognition(pair.name, location, outputArray, pair.distance);
  }

  //TODO  looks for the nearest embeeding in the database and returns the pair which contain information of registered face with which face is most similar
  /// [emb] 와 가장 닮은 등록 얼굴을 찾아 (이름, 유사도) 쌍으로 돌려준다.
  ///
  /// **코사인 유사도**를 쓴다. 두 벡터가 이루는 각도가 작을수록(방향이 비슷할수록)
  /// 1.0 에 가까워지고, 반대 방향이면 -1.0 에 가까워진다.
  /// 즉 **값이 클수록 더 닮은 것**이다.
  ///
  /// ⚠️ 등록된 얼굴이 하나도 없으면 `("Unknown", -1)` 이 그대로 반환된다.
  ///
  /// ⚠️ **아직 임계값(threshold) 판정이 없다.** 전혀 다른 사람이어도 무조건
  /// "가장 덜 다른 사람"의 이름을 돌려준다. 실제로 쓰려면 아래처럼
  /// 일정 기준 미만이면 Unknown 으로 처리하는 코드를 추가해야 한다.
  /// 예) `if (pair.distance < 0.8) pair.name = "Unknown";`
  ///     (0.8 은 예시 값이며 모델과 환경에 맞게 직접 실험해 정해야 한다)
  Pair findNearest(List<double> emb) {
    // 기본값: 아무도 못 찾았을 때의 결과
    Pair pair = Pair("Unknown", -1);

    // 등록된 얼굴을 하나씩 순회하며 유사도를 계산한다.
    for (MapEntry<String, Recognition> item in registered.entries) {
      final String name = item.key;
      List<double> knownEmb = item.value.embeddings;

      // 코사인 유사도 = (A·B) / (|A| * |B|)
      // dot   : 두 벡터의 내적 (A·B)
      // normA : A 길이의 제곱 (아래에서 sqrt 를 씌운다)
      // normB : B 길이의 제곱
      double dot = 0;
      double normA = 0;
      double normB = 0;
      for (int i = 0; i < emb.length; i++) {
        dot += emb[i] * knownEmb[i];
        normA += emb[i] * emb[i];
        normB += knownEmb[i] * knownEmb[i];
      }

      double similarity = dot / (sqrt(normA) * sqrt(normB));

      // Cosine similarity is between -1 and 1, where 1 means most similar
      // 지금까지 중 가장 높은 유사도면 갱신한다.
      if (pair.distance == -1 || similarity > pair.distance) {
        pair.distance = similarity;
        pair.name = name;
      }
    }

    return pair;
  }

  /// 모델을 메모리에서 내린다. 화면이 사라질 때 호출해 자원을 정리한다.
  void close() {
    interpreter.close();
  }
}

/// (이름, 유사도) 두 값을 묶어서 돌려주기 위한 아주 단순한 클래스.
///
/// Dart 함수는 값을 하나만 반환할 수 있어서, 두 개를 함께 주려고 만든 그릇이다.
/// (요즘 Dart 라면 record 타입 `(String, double)` 로 대체할 수도 있다)
class Pair {
  /// 가장 닮은 사람 이름. 없으면 "Unknown".
  String name;

  /// 코사인 유사도. 이름과 달리 **클수록 닮은 것**이다.
  double distance;

  Pair(this.name, this.distance);
}
