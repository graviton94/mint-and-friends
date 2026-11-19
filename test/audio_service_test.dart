import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('테스트 환경에서는 오디오가 꺼져 있고 호출해도 예외가 없다', () async {
    SharedPreferences.setMockInitialValues({});
    expect(AudioService.enabled, isFalse);
    final a = AudioService.instance;
    expect(identical(a, AudioService()), isTrue);
    await a.init();
    for (final s in Sfx.values) {
      a.play(s);
    }
    await a.startMusic();
    await a.pauseMusic();
    await a.resumeMusic();
  });

  test('음악/효과음 토글은 값과 알림을 바꾼다', () async {
    final a = AudioService.instance;
    var notified = 0;
    void listener() => notified++;
    a.addListener(listener);
    await a.setMusic(false);
    await a.setSfx(false);
    expect(a.musicOn, isFalse);
    expect(a.sfxOn, isFalse);
    await a.setMusic(true);
    await a.setSfx(true);
    expect(a.musicOn, isTrue);
    expect(a.sfxOn, isTrue);
    expect(notified, 4);
    a.removeListener(listener);
  });

  test('효과음 파일 이름', () {
    expect(Sfx.mergeBig.asset, 'audio/merge_big.ogg');
    expect(Sfx.values.length, 14);
  });
}
