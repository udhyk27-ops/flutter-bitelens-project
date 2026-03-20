import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

import '../services/api_service.dart';
import '../services/database_service.dart';

class ResultScreen extends StatefulWidget {
  final String imagePath;

  const ResultScreen({super.key, required this.imagePath});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  String _result = '';
  bool _isLoading = true;

  late AnimationController _scanController;
  late Animation<double> _scanAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _analyzeFood();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _analyzeFood() async {
    /// 네트워크 확인
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      setState(() {
        _result = '인터넷 연결을 확인해주세요.';
        _isLoading = false;
      });
      _scanController.stop();
      _fadeController.forward();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final saveHistory = prefs.getBool('save_history') ?? true;
    final detailedAnalysis = prefs.getBool('detailed_analysis') ?? false;
    final language = prefs.getString('response_language') ?? '한국어';

    try {
      final rawBytes = await File(widget.imagePath).readAsBytes();
      final isJpeg = rawBytes[0] == 0xFF && rawBytes[1] == 0xD8 && rawBytes[2] == 0xFF;
      final imageBytes = isJpeg
          ? rawBytes
          : await compute(_convertToJpeg, rawBytes);

      // Functions 호출
      final response = await http.post(
        Uri.parse('https://analyzefood-mfdr4grlbq-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': base64Encode(imageBytes),
          'detailedAnalysis': detailedAnalysis,
          'language': language,
          'aiModel': Api().aiModel,
        }),
      );

      final data = jsonDecode(response.body);

      setState(() {
        _result = data['result'] ?? '분석 실패';
        _isLoading = false;
      });

      _scanController.stop();
      _fadeController.forward();

      if (saveHistory) {
        await DatabaseHelper.instance.insertAnalysis(
          imagePath: widget.imagePath,
          result: _result,
        );
      }
    } catch (e) {
      print('오류 발생: $e');
      setState(() {
        _result = '오류가 발생했습니다.';
        _isLoading = false;
      });
      _scanController.stop();
      _fadeController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ANALYSIS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
        centerTitle: true,
        actions: [
          // 로딩 끝났을 때만 공유 버튼 표시
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.ios_share, color: Colors.white, size: 20),
              onPressed: _shareResult,
            ),
        ],
      ),

      body: Column(
        children: [
          // 이미지 + 스캔 애니메이션
          SizedBox(
            height: 320,
            width: double.infinity,
            child: Stack(
              children: [
                // 사진
                Positioned.fill(
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.cover,
                  ),
                ),

                // 어두운 오버레이
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.35),
                  ),
                ),

                // 하단 페이드
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: 80,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black, Colors.transparent],
                      ),
                    ),
                  ),
                ),

                // 스캔 라인
                if (_isLoading)
                  AnimatedBuilder(
                    animation: _scanAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: _scanAnimation.value * 300,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            Container(
                              height: 1.5,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.deepOrange.withOpacity(0.6),
                                    Colors.orange,
                                    Colors.deepOrange.withOpacity(0.6),
                                    Colors.transparent,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.orange.withOpacity(0.1),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                // 코너 프레임
                if (_isLoading)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                      child: CustomPaint(painter: _FramePainter()),
                    ),
                  ),

                // 로딩 텍스트
                if (_isLoading)
                  Positioned(
                    bottom: 24,
                    left: 0, right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              color: Colors.orange,
                              strokeWidth: 1.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'AI 분석 중...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 결과 영역
          Expanded(
            child: _isLoading
                ? const SizedBox()
                : FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 결과 헤더
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '분석 결과',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 결과 텍스트
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.07),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _result,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.8,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.white24, size: 14),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'AI 분석 결과는 참고용이며, 음식의 종류·양·조리법에 따라 실제 칼로리와 영양소는 다를 수 있습니다.',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 11,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 다시 찍기 버튼
          if (!_isLoading)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          '다시 찍기',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// share
  Future<void> _shareResult() async {
    try {
      // 텍스트 + 이미지 함께 공유
      await Share.shareXFiles(
        [XFile(widget.imagePath)],
        text: _result,
        subject: 'BiteLens 음식 분석 결과',
      );
    } catch (e) {
      debugPrint('공유 오류: $e');
    }
  }
}

// 스캔 프레임 페인터
class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    const r = 10.0;

    // 좌상단
    canvas.drawLine(Offset(r, 0), Offset(len, 0), paint);
    canvas.drawLine(Offset(0, r), Offset(0, len), paint);
    canvas.drawArc(const Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14, 1.57, false, paint);

    // 우상단
    canvas.drawLine(Offset(size.width - len, 0), Offset(size.width - r, 0), paint);
    canvas.drawLine(Offset(size.width, r), Offset(size.width, len), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, 0, r * 2, r * 2), 4.71, 1.57, false, paint);

    // 좌하단
    canvas.drawLine(Offset(0, size.height - len), Offset(0, size.height - r), paint);
    canvas.drawLine(Offset(r, size.height), Offset(len, size.height), paint);
    canvas.drawArc(Rect.fromLTWH(0, size.height - r * 2, r * 2, r * 2), 1.57, 1.57, false, paint);

    // 우하단
    canvas.drawLine(Offset(size.width, size.height - len), Offset(size.width, size.height - r), paint);
    canvas.drawLine(Offset(size.width - len, size.height), Offset(size.width - r, size.height), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, size.height - r * 2, r * 2, r * 2), 0, 1.57, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Uint8List _convertToJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes)!;
  final jpeg = img.JpegEncoder().encode(decoded);
  return Uint8List.fromList(jpeg);
}
