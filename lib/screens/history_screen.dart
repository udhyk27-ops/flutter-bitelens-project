import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bitelens/services/database_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final data = await DatabaseHelper.instance.getAnalysisHistory();
    setState(() {
      _history = data;
      _isLoading = false;
    });
  }

  Future<void> _deleteItem(int id) async {
    await DatabaseHelper.instance.deleteAnalysis(id);
    await _loadHistory();
  }

  String _formatDate(String isoDate) {
    final dt = DateTime.parse(isoDate);
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // result 텍스트에서 음식 이름 파싱
  String _parseFoodName(String result) {
    final lines = result.split('\n');
    for (final line in lines) {
      if (line.contains('음식 이름')) {
        final parts = line.split(':');
        if (parts.length > 1) return parts[1].trim();
      }
    }
    return '음식';
  }

  // result 텍스트에서 칼로리 파싱
  String _parseCalories(String result) {
    final lines = result.split('\n');
    for (final line in lines) {
      if (line.contains('칼로리')) {
        final parts = line.split(':');
        if (parts.length > 1) return parts[1].trim();
      }
    }
    return '-';
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
          'HISTORY',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 1,
        ),
      )
          : _history.isEmpty
          ? _buildEmpty()
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final item = _history[index];
          return _HistoryCard(
            imagePath: item['image_path'],
            foodName: _parseFoodName(item['result']),
            calories: _parseCalories(item['result']),
            date: _formatDate(item['created_at']),
            result: item['result'],
            onDelete: () => _showDeleteDialog(item['id']),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 56,
            color: Colors.white12,
          ),
          const SizedBox(height: 16),
          const Text(
            '분석 기록이 없어요',
            style: TextStyle(
              color: Colors.white30,
              fontSize: 15,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '음식을 촬영해서 분석해보세요',
            style: TextStyle(
              color: Colors.white12,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '기록 삭제',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          '이 기록을 삭제할까요?',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteItem(id);
            },
            child: const Text('삭제', style: TextStyle(color: Colors.deepOrange)),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final String imagePath;
  final String foodName;
  final String calories;
  final String date;
  final String result;
  final VoidCallback onDelete;

  const _HistoryCard({
    required this.imagePath,
    required this.foodName,
    required this.calories,
    required this.date,
    required this.result,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetailSheet(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, // ← 추가
            children: [
              // 썸네일
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                child: File(imagePath).existsSync()
                    ? Image.file(
                  File(imagePath),
                  width: 90,
                  // height: 90 ← 이거 제거
                  fit: BoxFit.cover,
                )
                    : Container(
                  width: 90,
                  // height: 90 ← 이거 제거
                  color: const Color(0xFF1E1E1E),
                  child: const Icon(Icons.image_not_supported,
                      color: Colors.white12, size: 28),
                ),
              ),

              // 내용
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // ← 추가
                    children: [
                      Text(
                        foodName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        // maxLines: 1 ← 제거
                        // overflow: TextOverflow.ellipsis ← 제거
                      ),
                      // ... 나머지 동일
                    ],
                  ),
                ),
              ),

              // 삭제 버튼
              Align(
                alignment: Alignment.topCenter, // ← 삭제버튼 상단 고정
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.white12, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 핸들
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이미지
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: File(imagePath).existsSync()
                          ? Image.file(
                        File(imagePath),
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      )
                          : Container(
                        height: 200,
                        color: const Color(0xFF1E1E1E),
                        child: const Center(
                          child: Icon(Icons.image_not_supported,
                              color: Colors.white12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 헤더
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
                    const SizedBox(height: 16),

                    // 결과
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                      child: Text(
                        result,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.8,
                        ),
                      ),
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
}