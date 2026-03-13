import 'package:firebase_remote_config/firebase_remote_config.dart';

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

  Future<void> getRemoteConfig() async {
    try {
      final FirebaseRemoteConfig rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero,
      ));

      await rc.fetchAndActivate();

      appVersion = rc.getString('app_version_aos');
      storeUrl = rc.getString('store_aos');

      print('appVersion: $appVersion');
      print('storeUrl: $storeUrl');

      // print("REMOTE CONFIG 로드 완료: ${onBoardText.keys}");
    } catch (e) {
      print('REMOTE CONFIG ERROR: $e');
    }
  }
}