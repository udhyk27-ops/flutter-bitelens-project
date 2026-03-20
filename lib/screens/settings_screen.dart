import 'package:bitelens/screens/webview_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saveHistory = true; // 분석 기록 저장
  bool _detailedAnalysis = false; // 상세 분석
  String _selectedLanguage = '한국어';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 불러오기
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _saveHistory = prefs.getBool('save_history') ?? true;
      _detailedAnalysis = prefs.getBool('detailed_analysis') ?? false;
      _selectedLanguage = prefs.getString('response_language') ?? '한국어';
    });
  }

  // 저장
  Future<void> _saveSetting(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // 앱 정보 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.restaurant, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BITE LENS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Version ${Api().appVersion}',
                        style: TextStyle(color: Colors.white30, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // 분석 설정
            _SectionHeader(title: '분석 설정'),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _ToggleItem(
                  icon: Icons.history_outlined,
                  title: '분석 기록 저장',
                  subtitle: '분석 결과를 기기에 저장합니다',
                  value: _saveHistory,
                  onChanged: (val) async {
                    setState(() => _saveHistory = val);
                    await _saveSetting('save_history', val); // 기기 저장
                  },
                ),
                _Divider(),
                _ToggleItem(
                  icon: Icons.hd_outlined,
                  title: '상세분석',
                  subtitle: '응답이 느려질 수 있습니다',
                  value: _detailedAnalysis,
                  onChanged: (val) async {
                    setState(() => _detailedAnalysis = val);
                    await _saveSetting('detailed_analysis', val); // 저장
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 언어 설정
            _SectionHeader(title: '언어'),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _SelectItem(
                  icon: Icons.language_outlined,
                  title: '응답 언어',
                  value: _selectedLanguage,
                  options: ['한국어', 'English', '日本語'],
                  onChanged: (val) async {
                    setState(() => _selectedLanguage = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('response_language', val);
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 데이터
            _SectionHeader(title: '데이터'),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _ActionItem(
                  icon: Icons.delete_sweep_outlined,
                  title: '분석 기록 전체 삭제',
                  titleColor: Colors.red.shade300,
                  iconColor: Colors.red.shade300,
                  onTap: () => _showClearHistoryDialog(),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 앱 정보
            _SectionHeader(title: '앱 정보'),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _ActionItem(
                  icon: Icons.description_outlined,
                  title: '개인정보 처리방침',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WebViewScreen(
                          url: Api().privacyUrl,
                          title: '개인정보 처리방침',
                        ),
                      ),
                    );
                  },
                ),
                _Divider(),
                _ActionItem(
                  icon: Icons.info_outline,
                  title: '오픈소스 라이선스',
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'BiteLens',
                      applicationVersion: '1.0.0',
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '기록 전체 삭제',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          '모든 분석 기록이 삭제됩니다.\n이 작업은 되돌릴 수 없어요.',
          style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.clearAll();
              Navigator.pop(context);
            },
            child: Text('삭제', style: TextStyle(color: Colors.red.shade300)),
          ),
        ],
      ),
    );
  }
}

// 섹션 헤더
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white30,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

// 설정 카드 컨테이너
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(children: children),
    );
  }
}

// 토글 아이템
class _ToggleItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white24, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.deepOrange,
            activeTrackColor: Colors.deepOrange.withOpacity(0.3),
            inactiveThumbColor: Colors.white24,
            inactiveTrackColor: Colors.white10,
          ),
        ],
      ),
    );
  }
}

// 선택 아이템
class _SelectItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _SelectItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          DropdownButton<String>(
            value: value,
            dropdownColor: const Color(0xFF1A1A1A),
            underline: const SizedBox(),
            icon: const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            style: const TextStyle(color: Colors.white54, fontSize: 13),
            items: options
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) => val != null ? onChanged(val) : null,
          ),
        ],
      ),
    );
  }
}

// 액션 아이템
class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color titleColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.title,
    this.titleColor = Colors.white70,
    this.iconColor = Colors.white38,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: TextStyle(color: titleColor, fontSize: 14)),
            ),
            const Icon(Icons.chevron_right, color: Colors.white12, size: 18),
          ],
        ),
      ),
    );
  }
}

// 구분선
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 54),
      height: 0.5,
      color: Colors.white.withOpacity(0.06),
    );
  }
}