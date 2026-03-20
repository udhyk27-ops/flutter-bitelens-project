import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'package:camera/camera.dart';

class OnboardingScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const OnboardingScreen({super.key, required this.cameras});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final List<_OnboardingData> _pages = const [
    _OnboardingData(
      icon: Icons.camera_alt_outlined,
      title: 'AI 음식 스캔',
      subtitle: '음식을 찍으면\nAI가 칼로리와\n영양소를 분석해요',
      accent: Colors.deepOrange,
    ),
    _OnboardingData(
      icon: Icons.local_fire_department_outlined,
      title: '맞춤 칼로리 기준',
      subtitle: '내 신체 정보를 입력하면\n하루 권장 칼로리를\n자동으로 계산해드려요',
      accent: Color(0xFFFF7043),
    ),
    _OnboardingData(
      icon: Icons.show_chart,
      title: '섭취 기록 추적',
      subtitle: '매일의 식사를 기록하고\n칼로리 추이를\n한눈에 확인하세요',
      accent: Color(0xFFFF8A65),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding({bool goProfile = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;

    if (goProfile) {
      // 홈을 스택 바닥에 깔고 프로필을 그 위에 올림
      // 뒤로가기 시 홈으로 자연스럽게 이동
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(cameras: widget.cameras)),
      );
      await Future.delayed(Duration.zero); // 빌드 완료 후 push
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(cameras: widget.cameras)),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            children: [
              // 건너뛰기
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 24, 0),
                  child: GestureDetector(
                    onTap: () => _completeOnboarding(),
                    child: const Text('건너뛰기',
                        style: TextStyle(color: Colors.white24, fontSize: 13)),
                  ),
                ),
              ),

              // 페이지
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemCount: _pages.length,
                  itemBuilder: (_, i) => _OnboardingPage(data: _pages[i]),
                ),
              ),

              // 인디케이터
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? Colors.deepOrange : Colors.white12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),

              const SizedBox(height: 40),

              // 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: _currentPage < _pages.length - 1
                    ? _PrimaryButton(
                  label: '다음',
                  onTap: _nextPage,
                )
                    : Column(
                  children: [
                    _PrimaryButton(
                      label: '내 정보 입력하고 시작',
                      onTap: () => _completeOnboarding(goProfile: true),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _completeOnboarding(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text('나중에 설정할게요',
                              style: TextStyle(color: Colors.white38, fontSize: 15)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 온보딩 페이지 ────────────────────────────────────────────────────

class _OnboardingData {
  final IconData icon;
  final String title, subtitle;
  final Color accent;
  const _OnboardingData({
    required this.icon, required this.title,
    required this.subtitle, required this.accent,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingData data;
  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 아이콘 컨테이너
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              color: data.accent.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: data.accent.withOpacity(0.2), width: 1.5),
            ),
            child: Icon(data.icon, color: data.accent, size: 52),
          ),

          const SizedBox(height: 48),

          // 앱 이름
          const Text('BITE LENS',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 11,
              letterSpacing: 4,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 12),

          // 타이틀
          Text(data.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          // 서브타이틀
          Text(data.subtitle,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 16,
              height: 1.7,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.deepOrange,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}