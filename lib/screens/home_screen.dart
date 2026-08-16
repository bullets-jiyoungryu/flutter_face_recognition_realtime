import 'package:flutter/material.dart';
import 'recognition_screen.dart';
import 'registered_faces_screen.dart';
import 'registration_screen.dart';

/// 앱을 켜면 보이는 첫 화면. 세 개의 기능으로 들어가는 입구 역할만 한다.
///
/// 화면 안에서 바뀌는 값(상태)이 전혀 없기 때문에 **StatelessWidget** 이다.
/// 반대로 카메라 화면들은 계속 값이 바뀌므로 StatefulWidget 을 쓴다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 기기 화면의 가로 길이(픽셀). 아래에서 로고 크기를 화면 비율에 맞추는 데 쓴다.
    // 이렇게 하면 작은 폰과 태블릿에서 모두 자연스럽게 보인다.
    final screenWidth = MediaQuery.of(context).size.width;

    // Scaffold: 앱바/본문/하단바 등 화면의 기본 뼈대를 잡아주는 위젯.
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      // SafeArea: 상단 노치나 하단 홈 인디케이터에 UI가 가려지지 않게 여백을 준다.
      body: SafeArea(
        // Column: 자식들을 세로로 차례차례 배치한다.
        child: Column(
          children: [
            // SizedBox: 내용 없이 빈 공간(여백)만 만들 때 자주 쓰는 위젯.
            const SizedBox(height: 24),

            // Header Text
            // ── 상단 제목 영역 ──────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              // Row: 자식들을 가로로 나란히 배치한다.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tag_faces, size: 30, color: Colors.deepPurple),
                  SizedBox(width: 10),
                  Text(
                    "Face Recognition",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Logo
            // ── 가운데 원형 로고 ────────────────────────────
            Center(
              child: Container(
                // 화면 가로의 55% 크기로 정사각형을 만든다 (원이 찌그러지지 않도록).
                width: screenWidth * 0.55,
                height: screenWidth * 0.55,
                decoration: BoxDecoration(
                  // shape: circle 이라 정사각형 컨테이너가 원으로 보인다.
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      // withAlpha(80): 불투명도를 0~255 중 80으로 (연한 보라 그림자).
                      color: Colors.deepPurple.withAlpha(80),
                      spreadRadius: 5,
                      blurRadius: 15,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  image: const DecorationImage(
                    // 이미지 파일은 pubspec.yaml 의 assets 에 등록되어 있어야 한다.
                    // 파일을 바꾸려면 images/logo.png 를 교체하면 된다.
                    image: AssetImage("images/logo.png"),
                    fit: BoxFit.fitWidth,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Buttons as Cards
            // ── 기능 카드 3개 ───────────────────────────────
            // Expanded: Column 안에서 "남은 공간을 전부 차지하라"는 뜻.
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    // 💡 카드를 추가하고 싶다면 아래 _actionCard(...) 를 복사해
                    //    icon/title/subtitle/onTap 만 바꿔 넣으면 된다.
                    _actionCard(
                      context,
                      icon: Icons.person_add,
                      title: "Register New Face",
                      subtitle: "Capture and store a new user face",
                      // Navigator.push: 새 화면을 현재 화면 위에 쌓는다.
                      // 뒤로가기를 누르면 자동으로 이 화면으로 돌아온다.
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegistrationScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _actionCard(
                      context,
                      icon: Icons.search,
                      title: "Recognize Face",
                      subtitle: "Identify registered faces in real-time",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RecognitionScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _actionCard(
                      context,
                      icon: Icons.list,
                      title: "Registered Faces",
                      subtitle: "View all stored face data",
                      // 위 두 개는 화살표 함수(`=>`), 이건 중괄호 블록으로 썼다.
                      // 동작은 같으며 여러 줄을 쓸 수 있다는 점만 다르다.
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisteredFacesScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 기능 카드 하나를 만들어 돌려주는 재사용 함수.
  ///
  /// 똑같이 생긴 카드를 세 번 복사해 붙이는 대신, 이렇게 함수로 빼두면
  /// 디자인을 바꿀 때 한 곳만 고치면 전부 반영된다.
  ///
  /// `{ }` 로 감싼 파라미터는 **이름 붙은 인자(named parameter)** 라서
  /// 호출할 때 `icon: ..., title: ...` 처럼 이름을 적어야 하고 순서는 자유롭다.
  /// `required` 는 생략할 수 없다는 뜻이다.
  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    // GestureDetector: 자식 위젯이 탭(터치)에 반응하게 만들어 준다.
    return GestureDetector(
      onTap: onTap,
      child: Card(
        // elevation: 그림자 깊이. 클수록 카드가 떠 보인다.
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Row(
            children: [
              // 왼쪽 동그란 아이콘
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.deepPurple.shade50,
                child: Icon(icon, size: 30, color: Colors.deepPurple),
              ),
              const SizedBox(width: 20),
              // Expanded 로 감싸야 가운데 텍스트가 남은 가로 공간을 차지하고,
              // 글자가 길어져도 오른쪽 화살표를 밀어내지 않는다.
              Expanded(
                child: Column(
                  // 텍스트를 왼쪽 정렬한다.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // 오른쪽 ">" 화살표
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.deepPurple,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
