import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class Api {

  // --- 싱글톤 ---
  static final Api _instance = Api._internal();
  // → 클래스당 한 번만 생성되는 유일한 인스턴스

  factory Api() => _instance;
  // → 생성자를 factory로 만들어
  //   항상 기존 인스턴스를 반환하도록 제어

  Api._internal();
  // → 외부에서 new Api()를 막기 위한
  //   private 생성자

  // 인스턴스에 변수 저장
  String appVersion = "";
  String storeUrl = "";
  String aiModel = "";
  String privacyUrl = "";
  String termsUrl = "";

  Future<void> getRemoteConfig() async {

    try {
      final FirebaseRemoteConfig rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // 개발 중엔 즉시 반영(zero), 릴리스에선 매 실행 fetch를 피해
        // 스플래시 지연·데이터 소모·rate limit을 줄인다.
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(hours: 1),
      ));

      await rc.fetchAndActivate();

      aiModel = rc.getString('ai_model');
      appVersion = rc.getString('app_version_aos');
      storeUrl = rc.getString('store_aos');
      privacyUrl = rc.getString('privacy');
      termsUrl = rc.getString('terms');

    } catch (e) {
      debugPrint('REMOTE CONFIG ERROR: $e');
    }
  }
}