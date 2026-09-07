import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

import '../models/food_analysis.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/analysis_edit_sheet.dart';

/// 분석 실패 사유를 사용자에게 그대로 전달하기 위한 예외.
/// 상태코드별 메시지가 일반 catch(e)에서 "분석 중 오류"로 뭉개지지 않도록
/// 별도 타입으로 구분한다.
class _AnalyzeException implements Exception {
  final String message;
  const _AnalyzeException(this.message);
  @override
  String toString() => message;
}

class ResultScreen extends StatefulWidget {
  final String imagePath;

  const ResultScreen({super.key, required this.imagePath});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  /// 음식 분석 Cloud Function 엔드포인트(us-central1, 고정 URL).
  static const String _analyzeUrl =
      'https://analyzefood-mfdr4grlbq-uc.a.run.app';

  String _result = '';
  FoodAnalysis? _analysis; // 현재 표시값(배수 반영)
  FoodAnalysis? _baseAnalysis; // AI 추정 1인분 기준값
  double _portion = 1.0; // 먹은 양 배수
  int? _savedId; // 저장된 히스토리 row id (배수/보정 변경 시 갱신)
  bool _saveHistory = true;
  String _meal = mealForDate(DateTime.now()); // 끼니 태그
  bool _isLoading = true;
  double? _tdee;

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
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final tdee = prefs.getDouble('tdee');
    if (tdee != null) setState(() => _tdee = tdee);

    final connectivity = await Connectivity().checkConnectivity();
    if (!mounted) return;
    if (connectivity.contains(ConnectivityResult.none)) {
      setState(() {
        _result = '인터넷 연결을 확인해주세요.';
        _isLoading = false;
      });
      _scanController.stop();
      _fadeController.forward();
      return;
    }

    final saveHistory = prefs.getBool('save_history') ?? true;
    _saveHistory = saveHistory;
    final detailedAnalysis = prefs.getBool('detailed_analysis') ?? false;
    final language = prefs.getString('response_language') ?? '한국어';

    try {
      final rawBytes = await File(widget.imagePath).readAsBytes();
      if (rawBytes.length < 3) {
        _setError('이미지를 읽을 수 없습니다. 다른 사진을 사용해주세요.');
        return;
      }
      // 업로드 전 다운스케일(별도 isolate) — 전송량·Gemini 입력 비용 절감,
      // 서버 용량 상한 준수. 디코딩 실패 시 원본 바이트로 폴백.
      Uint8List imageBytes;
      String mimeType;
      try {
        imageBytes = await compute(_prepareImage, rawBytes);
        mimeType = 'image/jpeg'; // _prepareImage는 항상 JPEG로 인코딩
      } catch (e) {
        debugPrint('이미지 리사이즈 실패, 원본 사용: $e');
        imageBytes = rawBytes;
        mimeType = _detectMime(rawBytes); // 원본 포맷(HEIC/PNG 등)을 그대로 전달
      }

      // App Check 토큰 발급·부착은 _postWithRetry 내부에서 처리한다
      // (401 수신 시 토큰을 강제 갱신해 재시도할 수 있도록).
      final result = await _postWithRetry(
        base64Image: base64Encode(imageBytes),
        imageMimeType: mimeType,
        detailedAnalysis: detailedAnalysis,
        language: language,
        aiModel: Api().aiModel,
      );

      final analysis = FoodAnalysis.parse(result); // 1인분 기준

      if (!mounted) return; // 최대 30초 네트워크 후 — 화면 이탈 시 setState 방지
      setState(() {
        _result = result;
        _baseAnalysis = analysis;
        _analysis = analysis;
        _isLoading = false;
      });

      _scanController.stop();
      _fadeController.forward();

      if (saveHistory && analysis.hasNutrition) {
        _savedId = await DatabaseHelper.instance.insertAnalysis(
          imagePath: widget.imagePath,
          result: analysis.toJsonString(),
          meal: _meal,
        );
      }
    } on SocketException {
      _setError('네트워크 연결을 확인해주세요.');
    } on TimeoutException {
      _setError('분석 시간이 초과되었습니다. 다시 시도해주세요.');
    } on _AnalyzeException catch (e) {
      // 상태코드별 안내 메시지(앱 인증 실패/서버 혼잡 등)를 그대로 표시
      debugPrint('분석 오류: ${e.message}');
      _setError(e.message);
    } catch (e) {
      debugPrint('분석 오류: $e');
      _setError('분석 중 오류가 발생했습니다.');
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() { _result = msg; _isLoading = false; });
    _scanController.stop();
    _fadeController.forward();
  }

  /// 먹은 양(배수) 변경 → 표시값 재계산 및 저장된 기록 갱신
  Future<void> _setPortion(double factor) async {
    final base = _baseAnalysis;
    if (base == null || factor == _portion) return;
    setState(() {
      _portion = factor;
      _analysis = base.scale(factor);
    });
    final id = _savedId;
    if (id != null && _saveHistory) {
      await DatabaseHelper.instance
          .updateAnalysis(id, result: base.scale(factor).toJsonString());
    }
  }

  /// 결과 수동 보정 + 끼니 태그 편집. 보정 시 배수는 1로 초기화된다.
  Future<void> _openEdit() async {
    final current = _analysis;
    if (current == null) return;
    final res = await showAnalysisEditSheet(context, analysis: current, meal: _meal);
    if (res == null || !mounted) return;

    setState(() {
      _baseAnalysis = res.analysis;
      _analysis = res.analysis;
      _portion = 1.0;
      _meal = res.meal;
    });

    if (!_saveHistory) return;
    final id = _savedId;
    if (id != null) {
      await DatabaseHelper.instance
          .updateAnalysis(id, result: res.analysis.toJsonString(), meal: res.meal);
    } else if (res.analysis.hasNutrition) {
      // 처음엔 영양소가 없어 저장 안 됐다가, 보정으로 값이 생긴 경우 새로 저장
      _savedId = await DatabaseHelper.instance.insertAnalysis(
        imagePath: widget.imagePath,
        result: res.analysis.toJsonString(),
        meal: res.meal,
      );
    }
  }

  /// 최대 3회 재시도 (지수 백오프)
  ///
  /// App Check 토큰(등록된 앱임을 Cloud Function에 증명)을 매 시도마다 발급해
  /// `X-Firebase-AppCheck` 헤더로 부착한다. 401(인증 실패)을 받으면 캐시된
  /// 토큰이 만료/무효일 수 있으므로 `getToken(true)`로 강제 갱신 후 1회 재시도한다.
  Future<String> _postWithRetry({
    required String base64Image,
    required String imageMimeType,
    required bool detailedAnalysis,
    required String language,
    required String? aiModel,
    int maxRetries = 3,
  }) async {
    bool forceRefreshToken = false; // 401에 대한 강제 갱신은 1회로 제한

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      // 첫 시도는 캐시 토큰, 401 이후 시도는 강제 갱신된 토큰을 사용.
      // 발급 실패 시 토큰 없이 진행하되 원인을 로그로 남긴다(401의 근본 원인 추적용).
      String? appCheckToken;
      try {
        appCheckToken =
            await FirebaseAppCheck.instance.getToken(forceRefreshToken);
      } catch (e) {
        debugPrint(
            'App Check 토큰 발급 실패 (forceRefresh=$forceRefreshToken): $e');
      }

      try {
        final response = await http.post(
          Uri.parse(_analyzeUrl),
          headers: {
            'Content-Type': 'application/json',
            if (appCheckToken != null) 'X-Firebase-AppCheck': appCheckToken,
          },
          body: jsonEncode({
            'imageBase64': base64Image,
            'imageMimeType': imageMimeType,
            'detailedAnalysis': detailedAnalysis,
            'language': language,
            'aiModel': aiModel,
          }),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['result'] ?? '분석 결과를 받지 못했습니다.';
        } else if (response.statusCode == 401) {
          // 만료/무효 토큰일 수 있으므로 강제 갱신 후 1회 재시도.
          // (401 본문은 영문 진단 메시지라 사용자에게 노출하지 않는다.)
          if (!forceRefreshToken && attempt < maxRetries - 1) {
            debugPrint('App Check 401 → 토큰 강제 갱신 후 재시도');
            forceRefreshToken = true;
            continue;
          }
          throw const _AnalyzeException('앱 인증에 실패했습니다. 앱을 재시작해주세요.');
        } else if (response.statusCode == 429) {
          throw _AnalyzeException(
              _serverMessage(response) ?? '서버가 혼잡합니다. 잠시 후 다시 시도해주세요.');
        } else {
          // 서버가 내려준 안내 메시지(사진 분석 불가/용량 초과 등)를 그대로 표시,
          // 없으면 상태코드 폴백.
          throw _AnalyzeException(
              _serverMessage(response) ?? '서버 오류 (${response.statusCode})');
        }
      } on TimeoutException {
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: (attempt + 1) * 2));
      } on SocketException {
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: (attempt + 1) * 2));
      }
    }
    throw const _AnalyzeException('분석에 실패했습니다.');
  }

  /// 서버가 내려준 `{ "error": "..." }` 메시지를 안전하게 추출한다.
  /// 파싱 실패/빈 값이면 null(호출부에서 폴백 메시지 사용).
  String? _serverMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        final msg = (body['error'] as String).trim();
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {
      // JSON이 아니면 무시하고 폴백
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final parsedCalories = _isLoading ? null : _analysis?.calories;

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
          if (!_isLoading && _analysis != null && _analysis!.hasNutrition)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
              onPressed: _openEdit,
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.ios_share, color: Colors.white, size: 20),
              onPressed: _shareResult,
            ),
        ],
      ),

      body: Column(
        children: [
          SizedBox(
            height: 320,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  // 표시 영역 픽셀 폭으로 디코드를 제한 — 원본(수천만 화소)을
                  // 그대로 메모리에 올리지 않아 저사양 기기 OOM/버벅임을 방지.
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.cover,
                    cacheWidth: (MediaQuery.of(context).size.width *
                            MediaQuery.of(context).devicePixelRatio)
                        .round(),
                  ),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: 80,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black, Colors.transparent],
                      ),
                    ),
                  ),
                ),

                if (_isLoading)
                  AnimatedBuilder(
                    animation: _scanAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: _scanAnimation.value * 300,
                        left: 0, right: 0,
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
                                  BoxShadow(color: Colors.orange.withOpacity(0.5), blurRadius: 10, spreadRadius: 4),
                                ],
                              ),
                            ),
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.orange.withOpacity(0.1), Colors.transparent],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                if (_isLoading)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                      child: CustomPaint(painter: _FramePainter()),
                    ),
                  ),

                if (_isLoading)
                  Positioned(
                    bottom: 24, left: 0, right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 1.5),
                          ),
                          const SizedBox(width: 10),
                          const Text('AI 분석 중...',
                              style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1.5)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

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
                    Row(
                      children: [
                        Container(
                          width: 3, height: 18,
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('분석 결과',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1)),
                        const Spacer(),
                        if (_analysis != null && _analysis!.hasNutrition)
                          GestureDetector(
                            onTap: _openEdit,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: mealColorFor(_meal).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: mealColorFor(_meal).withOpacity(0.4)),
                              ),
                              child: Row(
                                children: [
                                  Text(_meal,
                                      style: TextStyle(color: mealColorFor(_meal), fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 4),
                                  Icon(Icons.edit, color: mealColorFor(_meal), size: 11),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.07)),
                      ),
                      child: Text(
                        _analysis?.displayText ?? _result,
                        style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.8, letterSpacing: 0.3),
                      ),
                    ),

                    if (_analysis != null && _analysis!.hasNutrition) ...[
                      const SizedBox(height: 12),
                      _PortionSelector(selected: _portion, onChanged: _setPortion),
                    ],

                    if (_analysis != null) ...[
                      const SizedBox(height: 12),
                      _NutritionCard(analysis: _analysis!),
                    ],

                    if (_tdee != null)
                      _TdeeBanner(tdee: _tdee!, parsedCalories: parsedCalories),

                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: Colors.white24, size: 14),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'AI 분석 결과는 참고용이며, 음식의 종류·양·조리법에 따라 실제 칼로리와 영양소는 다를 수 있습니다.',
                              style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.6),
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
                        child: Text('다시 찍기',
                            style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1)),
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

  Future<void> _shareResult() async {
    try {
      await Share.shareXFiles(
        [XFile(widget.imagePath)],
        text: _analysis?.displayText ?? _result,
        subject: 'BiteLens 음식 분석 결과',
      );
    } catch (e) {
      debugPrint('공유 오류: $e');
    }
  }
}

// ─── TDEE 기준선 배너 ─────────────────────────────────────────────────

class _TdeeBanner extends StatelessWidget {
  final double tdee;
  final int? parsedCalories;

  const _TdeeBanner({required this.tdee, this.parsedCalories});

  @override
  Widget build(BuildContext context) {
    final double? ratio = parsedCalories != null ? parsedCalories! / tdee : null;
    final double clampedRatio = (ratio ?? 0.0).clamp(0.0, 1.0);

    Color barColor;
    String comment;
    if (ratio == null) {
      barColor = Colors.white24;
      comment = '칼로리 정보를 파싱할 수 없었어요';
    } else if (ratio < 0.2) {
      barColor = Colors.green.shade400;
      comment = '가벼운 식사예요 👍';
    } else if (ratio < 0.4) {
      barColor = Colors.green.shade300;
      comment = '적당한 한 끼네요';
    } else if (ratio < 0.6) {
      barColor = Colors.orange.shade300;
      comment = '하루 권장량의 절반 이상이에요';
    } else {
      barColor = Colors.red.shade300;
      comment = '칼로리가 꽤 높은 편이에요';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_outlined, color: Colors.deepOrange, size: 16),
              const SizedBox(width: 8),
              const Text('일일 권장칼로리 기준',
                  style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)),
              const Spacer(),
              Text('${tdee.toStringAsFixed(0)} kcal',
                  style: const TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),

          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 6, color: Colors.white.withOpacity(0.07)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  height: 6,
                  width: (MediaQuery.of(context).size.width - 48 - 32) * clampedRatio,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              if (parsedCalories != null) ...[
                Text('${parsedCalories} kcal',
                    style: TextStyle(color: barColor, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text(
                  ratio != null ? '(${(ratio * 100).toStringAsFixed(0)}%)' : '',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const Spacer(),
              ],
              Text(comment, style: TextStyle(color: barColor, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 프로필 미설정 유도 배너 ─────────────────────────────────────────

class ProfileNudgeBanner extends StatelessWidget {
  final VoidCallback onTap;
  const ProfileNudgeBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.deepOrange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.deepOrange.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_add_outlined, color: Colors.deepOrange, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '프로필을 설정하면 칼로리 기준이 맞춤 설정돼요',
                style: TextStyle(color: Colors.deepOrange, fontSize: 12, height: 1.4),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.deepOrange, size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── 스캔 프레임 페인터 ───────────────────────────────────────────────

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

    canvas.drawLine(Offset(r, 0), Offset(len, 0), paint);
    canvas.drawLine(Offset(0, r), Offset(0, len), paint);
    canvas.drawArc(const Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14, 1.57, false, paint);

    canvas.drawLine(Offset(size.width - len, 0), Offset(size.width - r, 0), paint);
    canvas.drawLine(Offset(size.width, r), Offset(size.width, len), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, 0, r * 2, r * 2), 4.71, 1.57, false, paint);

    canvas.drawLine(Offset(0, size.height - len), Offset(0, size.height - r), paint);
    canvas.drawLine(Offset(r, size.height), Offset(len, size.height), paint);
    canvas.drawArc(Rect.fromLTWH(0, size.height - r * 2, r * 2, r * 2), 1.57, 1.57, false, paint);

    canvas.drawLine(Offset(size.width, size.height - len), Offset(size.width, size.height - r), paint);
    canvas.drawLine(Offset(size.width - len, size.height), Offset(size.width - r, size.height), paint);
    canvas.drawArc(Rect.fromLTWH(size.width - r * 2, size.height - r * 2, r * 2, r * 2), 0, 1.57, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 업로드용 이미지 준비(isolate에서 실행):
/// 최대 1024px로 축소 후 JPEG(품질 85)로 인코딩해 전송량과 Gemini 입력 비용을 낮춘다.
Uint8List _prepareImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('이미지 디코딩에 실패했습니다. 지원하지 않는 형식일 수 있습니다.');
  }
  const maxDim = 1024;
  img.Image out = decoded;
  if (decoded.width > maxDim || decoded.height > maxDim) {
    out = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxDim)
        : img.copyResize(decoded, height: maxDim);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

/// 원본 바이트의 매직넘버로 이미지 MIME을 추정한다(리사이즈 폴백 시 사용).
/// 서버가 허용 목록으로 재검증하므로 인식 실패 시 기본 jpeg를 반환한다.
String _detectMime(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 8 &&
      b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  // WebP: 'RIFF'....'WEBP'
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  // HEIC/HEIF: 'ftyp' 박스 뒤 브랜드(heic/heix/hevc/mif1 등)로 판별
  if (b.length >= 12 &&
      b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
    if (brand.startsWith('hei') ||
        brand.startsWith('hev') ||
        brand == 'mif1' ||
        brand == 'msf1') {
      return 'image/heic';
    }
  }
  return 'image/jpeg';
}

// ─── 영양소 시각화 카드 ───────────────────────────────────────────────

// ─── 먹은 양(1인분 배수) 선택기 ──────────────────────────────────────

class _PortionSelector extends StatelessWidget {
  final double selected;
  final ValueChanged<double> onChanged;
  const _PortionSelector({required this.selected, required this.onChanged});

  static const List<double> _options = [0.5, 1.0, 1.5, 2.0, 3.0];

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  String _label(double v) => '×${_num(v)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_outlined, color: Colors.deepOrange, size: 15),
              const SizedBox(width: 8),
              const Text('먹은 양',
                  style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)),
              const Spacer(),
              Text(
                selected == 1.0 ? '1인분 기준' : '${_num(selected)}인분',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: _options.map((v) {
              final isSel = v == selected;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => onChanged(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSel ? Colors.deepOrange : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel ? Colors.deepOrange : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _label(v),
                          style: TextStyle(
                            color: isSel ? Colors.white : Colors.white54,
                            fontSize: 13,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _NutritionCard extends StatelessWidget {
  final FoodAnalysis analysis;
  const _NutritionCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final carbsStr = analysis.carbsText ?? '-';
    final proteinStr = analysis.proteinText ?? '-';
    final fatStr = analysis.fatText ?? '-';
    final sodiumStr = analysis.sodiumText;
    final fiberStr = analysis.fiberText;

    final carbs = analysis.carbs ?? 0;
    final protein = analysis.protein ?? 0;
    final fat = analysis.fat ?? 0;
    final total = carbs + protein + fat;

    if (carbsStr == '-' && proteinStr == '-' && fatStr == '-') return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('영양소', style: TextStyle(color: Colors.white30, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 14),

          if (total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  return Row(children: [
                    Container(width: total > 0 ? carbs / total * w : 0, color: Colors.blue.shade300),
                    Container(width: total > 0 ? protein / total * w : 0, color: Colors.green.shade400),
                    Container(width: total > 0 ? fat / total * w : 0, color: Colors.orange.shade300),
                  ]);
                }),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              _Legend(color: Colors.blue.shade300, label: '탄 ${(carbs/total*100).toStringAsFixed(0)}%'),
              const SizedBox(width: 12),
              _Legend(color: Colors.green.shade400, label: '단 ${(protein/total*100).toStringAsFixed(0)}%'),
              const SizedBox(width: 12),
              _Legend(color: Colors.orange.shade300, label: '지 ${(fat/total*100).toStringAsFixed(0)}%'),
            ]),
            const SizedBox(height: 14),
          ],

          Row(children: [
            Expanded(child: _MacroCol(label: '탄수화물', value: carbsStr, color: Colors.blue.shade300)),
            Expanded(child: _MacroCol(label: '단백질', value: proteinStr, color: Colors.green.shade400)),
            Expanded(child: _MacroCol(label: '지방', value: fatStr, color: Colors.orange.shade300)),
          ]),

          if (sodiumStr != null || fiberStr != null) ...[
            const SizedBox(height: 12),
            Container(height: 0.5, color: Colors.white.withOpacity(0.06)),
            const SizedBox(height: 12),
            Row(children: [
              if (sodiumStr != null)
                Expanded(child: _MacroCol(label: '나트륨', value: sodiumStr, color: Colors.yellow.shade600)),
              if (fiberStr != null)
                Expanded(child: _MacroCol(label: '식이섬유', value: fiberStr, color: Colors.teal.shade300)),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ],
  );
}

class _MacroCol extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MacroCol({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
    ],
  );
}