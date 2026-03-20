import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _selectedGender = '남성';
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  String _selectedActivity = '보통 (주 3~5회 운동)';

  double? _bmi;
  double? _bmr;
  double? _tdee;

  List<Map<String, dynamic>> _weightLog = [];
  final _logWeightController = TextEditingController();

  final List<String> _activityOptions = [
    '거의 안 함 (사무직)',
    '가벼운 활동 (주 1~2회)',
    '보통 (주 3~5회 운동)',
    '활동적 (주 6~7회 운동)',
    '매우 활동적 (운동선수)',
  ];

  final Map<String, double> _activityMultiplier = {
    '거의 안 함 (사무직)': 1.2,
    '가벼운 활동 (주 1~2회)': 1.375,
    '보통 (주 3~5회 운동)': 1.55,
    '활동적 (주 6~7회 운동)': 1.725,
    '매우 활동적 (운동선수)': 1.9,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadWeightLog();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _logWeightController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedGender = prefs.getString('gender') ?? '남성';
      _selectedActivity = prefs.getString('activity') ?? '보통 (주 3~5회 운동)';
      _ageController.text = prefs.getString('age') ?? '';
      _heightController.text = prefs.getString('height') ?? '';
      _weightController.text = prefs.getString('weight') ?? '';
    });
    _calculate();
  }

  Future<void> _loadWeightLog() async {
    final log = await DatabaseHelper.instance.getWeightLog();
    setState(() => _weightLog = log);
  }

  Future<void> _saveBodyInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gender', _selectedGender);
    await prefs.setString('age', _ageController.text);
    await prefs.setString('height', _heightController.text);
    await prefs.setString('weight', _weightController.text);
    await prefs.setString('activity', _selectedActivity);
    if (_tdee != null) await prefs.setDouble('tdee', _tdee!);
  }

  void _calculate() {
    final age = double.tryParse(_ageController.text);
    final height = double.tryParse(_heightController.text);
    final weight = double.tryParse(_weightController.text);

    if (age == null || height == null || weight == null || height == 0) {
      setState(() { _bmi = null; _bmr = null; _tdee = null; });
      return;
    }

    final bmi = weight / ((height / 100) * (height / 100));
    final bmr = _selectedGender == '남성'
        ? 88.362 + (13.397 * weight) + (4.799 * height) - (5.677 * age)
        : 447.593 + (9.247 * weight) + (3.098 * height) - (4.330 * age);
    final multiplier = _activityMultiplier[_selectedActivity] ?? 1.55;

    setState(() {
      _bmi = bmi;
      _bmr = bmr;
      _tdee = bmr * multiplier;
    });
  }

  Future<void> _addWeightLog() async {
    final raw = _logWeightController.text.trim().replaceAll(',', '.');
    final val = double.tryParse(raw);
    if (val == null || val <= 0) return;
    await DatabaseHelper.instance.insertWeight(val);
    _logWeightController.clear();
    await _loadWeightLog();
    // 현재 몸무게도 갱신
    _weightController.text = val.toString();
    _calculate();
    await _saveBodyInfo();
  }

  Future<void> _deleteWeightLog(int id) async {
    await DatabaseHelper.instance.deleteWeight(id);
    await _loadWeightLog();
  }

  String _getBmiLabel(double bmi) {
    if (bmi < 18.5) return '저체중';
    if (bmi < 23.0) return '정상';
    if (bmi < 25.0) return '과체중';
    return '비만';
  }

  Color _getBmiColor(double bmi) {
    if (bmi < 18.5) return Colors.blue.shade300;
    if (bmi < 23.0) return Colors.green.shade400;
    if (bmi < 25.0) return Colors.orange.shade300;
    return Colors.red.shade400;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'MY PROFILE',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 6),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 안내 배너
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.deepOrange.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.deepOrange, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '입력한 정보를 기반으로 칼로리 분석 기준이 설정됩니다',
                        style: TextStyle(color: Colors.deepOrange, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ─── 신체 정보 ────────────────────────────────
              _SectionHeader(title: '신체 정보'),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline, color: Colors.white38, size: 20),
                        const SizedBox(width: 14),
                        const Text('성별', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const Spacer(),
                        _GenderToggle(
                          value: _selectedGender,
                          onChanged: (val) async {
                            setState(() => _selectedGender = val);
                            _calculate(); await _saveBodyInfo();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _HairLine(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _BodyInputField(
                          controller: _ageController, label: '나이', unit: '세',
                          onChanged: (_) async { _calculate(); await _saveBodyInfo(); },
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _BodyInputField(
                          controller: _heightController, label: '키', unit: 'cm',
                          onChanged: (_) async { _calculate(); await _saveBodyInfo(); },
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _BodyInputField(
                          controller: _weightController, label: '몸무게', unit: 'kg',
                          onChanged: (_) async { _calculate(); await _saveBodyInfo(); },
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _HairLine(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.directions_run_outlined, color: Colors.white38, size: 20),
                        const SizedBox(width: 14),
                        const Text('활동량', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _selectedActivity,
                          dropdownColor: const Color(0xFF1A1A1A),
                          underline: const SizedBox(),
                          icon: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          items: _activityOptions
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              setState(() => _selectedActivity = val);
                              _calculate(); await _saveBodyInfo();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ─── BMI / BMR 결과 ───────────────────────────
              if (_bmi != null && _bmr != null && _tdee != null) ...[
                _SectionHeader(title: '분석 결과'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BMI', style: TextStyle(color: Colors.white30, fontSize: 11, letterSpacing: 2)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_bmi!.toStringAsFixed(1),
                              style: TextStyle(color: _getBmiColor(_bmi!), fontSize: 40, fontWeight: FontWeight.w700, height: 1)),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getBmiColor(_bmi!).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(_getBmiLabel(_bmi!),
                                  style: TextStyle(color: _getBmiColor(_bmi!), fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _BmiGaugeBar(bmi: _bmi!),
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('저체중', style: TextStyle(color: Colors.white24, fontSize: 10)),
                          Text('정상', style: TextStyle(color: Colors.white24, fontSize: 10)),
                          Text('과체중', style: TextStyle(color: Colors.white24, fontSize: 10)),
                          Text('비만', style: TextStyle(color: Colors.white24, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _MetricCard(
                      label: '기초대사량', sublabel: 'BMR',
                      value: _bmr!.toStringAsFixed(0), unit: 'kcal',
                      icon: Icons.favorite_border, color: Colors.white70,
                      tooltip: '아무것도 하지 않아도\n심장 박동, 호흡, 체온 유지 등\n생명 활동에 소비되는 최소 칼로리예요.\n\n해리스-베네딕트 공식으로 계산되며\n성별·나이·키·몸무게를 기반으로 합니다.',
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _MetricCard(
                      label: '일일 권장칼로리', sublabel: 'TDEE',
                      value: _tdee!.toStringAsFixed(0), unit: 'kcal',
                      icon: Icons.local_fire_department_outlined, color: Colors.deepOrange,
                      tooltip: '하루 동안 실제로 소비하는\n총 칼로리예요.\n\nBMR × 활동량 계수로 산출되며\n이 수치가 음식 분석 시\n칼로리 기준선으로 사용됩니다.',
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '* 해리스-베네딕트 공식 기반 추정치입니다. 개인차가 있을 수 있어요.',
                    style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.calculate_outlined, color: Colors.white12, size: 40),
                      SizedBox(height: 12),
                      Text(
                        '신체 정보를 입력하면\nBMI와 기초대사량이 계산됩니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white24, fontSize: 13, height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ─── 몸무게 기록 ──────────────────────────────
              _SectionHeader(title: '몸무게 기록'),
              const SizedBox(height: 12),

              // 입력 행
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline, color: Colors.white38, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _logWeightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '오늘 몸무게 입력 (kg)',
                          hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _addWeightLog(),
                      ),
                    ),
                    GestureDetector(
                      onTap: _addWeightLog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('기록', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              if (_weightLog.isNotEmpty) ...[
                // 미니 라인 차트
                Container(
                  width: double.infinity,
                  height: 140,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: _WeightChart(logs: _weightLog),
                ),
                const SizedBox(height: 12),

                // 기록 목록 (최근 10개)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    children: () {
                      final reversed = _weightLog.reversed.take(10).toList();
                      return reversed.asMap().entries.map((entry) {
                        final i = entry.key;
                        final row = entry.value;
                        final weight = (row['weight'] as num).toDouble();
                        final date = DateTime.parse(row['logged_at'] as String);
                        final dateStr = '${date.month}/${date.day}';
                        final timeStr =
                            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                        double? diff;
                        if (i + 1 < reversed.length) {
                          diff = weight - (reversed[i + 1]['weight'] as num).toDouble();
                        }

                        return Column(
                          children: [
                            if (i > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 54),
                                height: 0.5,
                                color: Colors.white.withOpacity(0.05),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 38,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(dateStr, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                                        Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('${weight.toStringAsFixed(1)} kg',
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  if (diff != null)
                                    Text(
                                      diff > 0 ? '+${diff.toStringAsFixed(1)}' : diff.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: diff > 0 ? Colors.red.shade300 : Colors.green.shade400,
                                        fontSize: 12, fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => _deleteWeightLog(row['id'] as int),
                                    child: const Icon(Icons.close, color: Colors.white12, size: 18),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    }(),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.show_chart, color: Colors.white12, size: 32),
                      SizedBox(height: 10),
                      Text('기록을 추가하면 추이 그래프가 표시됩니다',
                          style: TextStyle(color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 몸무게 라인 차트 ──────────────────────────────────────────────────

class _WeightChart extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const _WeightChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.length < 2) {
      return const Center(
        child: Text('2개 이상 기록 시 그래프가 표시됩니다',
            style: TextStyle(color: Colors.white24, fontSize: 12)),
      );
    }
    final weights = logs.map((e) => (e['weight'] as num).toDouble()).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b) - 1;
    final maxW = weights.reduce((a, b) => a > b ? a : b) + 1;
    return CustomPaint(
      painter: _ChartPainter(weights: weights, minW: minW, range: maxW - minW),
      size: Size.infinite,
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> weights;
  final double minW;
  final double range;
  const _ChartPainter({required this.weights, required this.minW, required this.range});

  Offset _toOffset(int i, Size size) {
    final x = weights.length == 1 ? size.width / 2 : i / (weights.length - 1) * size.width;
    final y = range == 0 ? size.height / 2 : size.height - ((weights[i] - minW) / range * size.height);
    return Offset(x, y.clamp(4.0, size.height - 4.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2) return;

    // 채우기
    final fillPath = Path()..moveTo(0, size.height);
    for (int i = 0; i < weights.length; i++) {
      final o = _toOffset(i, size);
      fillPath.lineTo(o.dx, o.dy);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.deepOrange.withOpacity(0.3), Colors.deepOrange.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    );

    // 라인
    final linePath = Path();
    for (int i = 0; i < weights.length; i++) {
      final o = _toOffset(i, size);
      if (i == 0) linePath.moveTo(o.dx, o.dy);
      else linePath.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.deepOrange
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 점
    for (int i = 0; i < weights.length; i++) {
      final o = _toOffset(i, size);
      canvas.drawCircle(o, 4, Paint()..color = const Color(0xFF111111));
      canvas.drawCircle(o, 3, Paint()..color = Colors.deepOrange);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── 공통 위젯 ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(title.toUpperCase(),
        style: const TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2)),
  );
}

class _HairLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: Colors.white.withOpacity(0.06));
}

class _GenderToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _GenderToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: ['남성', '여성'].map((g) {
          final selected = value == g;
          return GestureDetector(
            onTap: () => onChanged(g),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? Colors.deepOrange : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(g, style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BodyInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label, unit;
  final ValueChanged<String> onChanged;
  const _BodyInputField({required this.controller, required this.label, required this.unit, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white30, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            onChanged: onChanged,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              border: InputBorder.none,
              hintText: unit,
              hintStyle: const TextStyle(color: Colors.white12, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _BmiGaugeBar extends StatelessWidget {
  final double bmi;
  const _BmiGaugeBar({required this.bmi});

  @override
  Widget build(BuildContext context) {
    final clamped = bmi.clamp(15.0, 35.0);
    final fraction = (clamped - 15.0) / 20.0;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(colors: [
                  Color(0xFF64B5F6), Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFE57373),
                ]),
              ),
            ),
            Positioned(
              left: (width * fraction - 4).clamp(0, width - 8),
              top: -1,
              child: Container(
                width: 8, height: 10,
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _MetricCard extends StatelessWidget {
  final String label, sublabel, value, unit, tooltip;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label, required this.sublabel,
    required this.value, required this.unit,
    required this.icon, required this.color,
    required this.tooltip,
  });

  void _showTooltip(BuildContext outerContext) {
    // 다이얼로그 열기 전에 포커스 먼저 해제
    FocusScope.of(outerContext).unfocus();
    showDialog(
      context: outerContext,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(sublabel,
                    style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ]),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 16),
              Container(height: 0.5, color: Colors.white12),
              const SizedBox(height: 16),
              Text(tooltip,
                  style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.7)),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(outerContext),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('확인', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(sublabel, style: TextStyle(color: color, fontSize: 11, letterSpacing: 1.5)),
            const Spacer(),
            GestureDetector(
              onTap: () => _showTooltip(context),
              child: const Icon(Icons.help_outline, color: Colors.white12, size: 15),
            ),
          ]),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 4),
          Text(unit, style: const TextStyle(color: Colors.white24, fontSize: 12)),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}