import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/format.dart';
import 'game/game_state.dart';
import 'services/ads_service.dart';
import 'services/billing_service.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

const _saveKey = 'save_v1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();
  var game = GameState();
  final raw = prefs.getString(_saveKey);
  if (raw != null) {
    try {
      if (!game.load(raw)) game = GameState(); // 예전 버전 저장
    } catch (_) {
      game = GameState(); // 손상된 저장 데이터는 무시하고 새로 시작
    }
  }

  final billing = BillingService();
  final ads = AdsService(isAdFree: () => billing.adFree);
  billing.addListener(() => game.adFree = billing.adFree);

  runApp(BloomApp(game: game, ads: ads, billing: billing, prefs: prefs));

  unawaited(billing.init());
  unawaited(ads.init());
}

class BloomApp extends StatefulWidget {
  const BloomApp({
    super.key,
    required this.game,
    required this.ads,
    required this.billing,
    required this.prefs,
  });
  final GameState game;
  final AdsService ads;
  final BillingService billing;
  final SharedPreferences prefs;

  @override
  State<BloomApp> createState() => _BloomAppState();
}

class _BloomAppState extends State<BloomApp> with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();
  Timer? _loop;
  Timer? _autosave;
  DateTime _lastTick = DateTime.now();

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerOffline());
  }

  void _start() {
    _lastTick = DateTime.now();
    _loop?.cancel();
    _loop = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now();
      final dt = now.difference(_lastTick).inMicroseconds / 1e6;
      _lastTick = now;
      game.tick(dt.clamp(0, 1)); // 긴 공백은 오프라인 보상으로 처리
    });
    _autosave?.cancel();
    _autosave = Timer.periodic(const Duration(seconds: 5), (_) => _save());
  }

  void _stop() {
    _loop?.cancel();
    _autosave?.cancel();
    _save();
  }

  void _save() => widget.prefs.setString(_saveKey, game.encode());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stop();
    } else if (state == AppLifecycleState.resumed) {
      _start();
      _offerOffline();
    }
  }

  Future<void> _offerOffline() async {
    final reward = game.computeOffline();
    final ctx = _navKey.currentContext;
    if (reward == null || ctx == null) return;
    final adFree = widget.billing.adFree;
    final doubled = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🌙 정원이 자라는 동안', textAlign: TextAlign.center),
        content: Text(
          '${fmtDuration(reward.away)} 동안\n🪙 ${fmt(reward.coins)} 을(를) 모았어요!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('받기', style: TextStyle(fontSize: 16)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.ad),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(adFree ? '2배로 받기' : '📺 2배로 받기'),
          ),
        ],
      ),
    );
    var x2 = false;
    if (doubled == true) x2 = await widget.ads.showRewarded();
    game.grantOffline(reward, doubled: x2);
    _save();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: '블룸 가든',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(game: game, ads: widget.ads, billing: widget.billing),
    );
  }
}
