import 'dart:math';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'art/art.dart';
import 'game/format.dart';
import 'game/game_state.dart';
import 'i18n/l10n.dart';
import 'i18n/names.dart';
import 'services/ads_service.dart';
import 'services/audio_service.dart';
import 'services/auth_service.dart';
import 'services/billing_service.dart';
import 'services/save_service.dart';
import 'services/social_service.dart';
import 'ui/account_ui.dart';
import 'ui/home_screen.dart';
import 'ui/sheets.dart';
import 'ui/social_ui.dart';
import 'ui/theme.dart';
import 'ui/widgets/icon_text.dart';
import 'ui/widgets/frame_box.dart';
import 'services/analytics_service.dart';
import 'services/remote_tuning.dart';
import 'services/dev_log.dart';
import 'ui/start_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 글자 · 그림 목록만 먼저 (스플래시를 그리는 데 필요): 나머지는 스플래시 뒤에서 진행도와 함께
  await Future.wait([L10n.instance.init(), Art.init()]);

  String version = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
  } catch (_) {}

  runApp(StartApp(boot: _boot, version: version));
}

/// 스플래시 동안 하는 무거운 준비. 단계마다 진행도를 알리고, 끝나면 게임 화면을 돌려준다.
Future<Widget> _boot(void Function(double) report) async {
  report(0.1);
  final prefs = await SharedPreferences.getInstance();
  final auth = AuthService();
  await auth.init();
  report(0.35);
  // 경제 변수 원격 조정 (오래 걸리면 기본값으로 시작)
  await RemoteTuning.load().timeout(
    const Duration(seconds: 3),
    onTimeout: () {},
  );
  report(0.55);
  await AudioService.instance.init();
  await DevLog.instance.init();
  report(0.75);

  final save = SaveService(prefs);
  final game = GameState();
  save.loadLocal(game);
  report(0.9);

  final billing = BillingService();
  // 친구 · 선물 · 공지 (Firebase 가 없으면 꺼진다: 메뉴에서 친구가 숨는다)
  final social = SocialService(
    backend: FirestoreSocialBackend(),
    prefs: prefs,
    uid: () => auth.uid,
    accountName: () => auth.isGuest ? null : auth.user?.displayName,
  );
  final ads = AdsService(isAdFree: () => billing.adFree);

  String version = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version} (${info.buildNumber})';
  } catch (_) {}

  unawaited(billing.init());
  unawaited(ads.init());
  report(1);
  return GameApp(
    game: game,
    ads: ads,
    billing: billing,
    auth: auth,
    save: save,
    social: social,
    version: version,
  );
}

class GameApp extends StatefulWidget {
  const GameApp({
    super.key,
    required this.game,
    required this.ads,
    required this.billing,
    required this.auth,
    required this.save,
    this.social,
    this.version = '',
  });
  final GameState game;
  final AdsService ads;
  final BillingService billing;
  final AuthService auth;
  final SaveService save;
  final SocialService? social;
  final String version;

  @override
  State<GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<GameApp> with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();
  late GameState game;
  Timer? _loop;
  Timer? _autosave;
  DateTime _lastTick = DateTime.now();
  String? _attachedUid;
  bool _attaching = false;
  StreamSubscription<GameEvent>? _gameSub;

  AuthService get auth => widget.auth;
  SaveService get save => widget.save;
  SocialService? get social => widget.social;
  late final Listenable _homeListen = Listenable.merge([save, ?widget.social]);

  @override
  void initState() {
    super.initState();
    game = widget.game;
    _bindGame();
    WidgetsBinding.instance.addObserver(this);
    widget.billing.addListener(() => game.adFree = widget.billing.adFree);
    // 다이아 결제 → 지금 게임에 넣고 바로 저장 (계정 전환 뒤에도 현재 game 을 쓴다)
    widget.billing.onGems = (n) {
      game.grantGems(n);
      save.saveLocal(game);
      save.upload(game);
    };
    auth.addListener(_onAuthChanged);
    _start();
    DevLog.instance.record(game, 'start');
    AudioService.instance.startMusic();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onAuthChanged();
      _offerOffline();
    });
  }

  /// 중요한 순간(레벨업, 장식, 구역 완성)에는 바로 클라우드에 올린다.
  void _bindGame() {
    Analytics.instance.attach(game);
    _gameSub?.cancel();
    _gameSub = game.events.listen((e) {
      if (e is LevelUpEvent) DevLog.instance.record(game, 'level');
      if (e is AreaCompletedEvent) DevLog.instance.record(game, 'area');
      if (e is LevelUpEvent ||
          e is DecorPlacedEvent ||
          e is AreaCompletedEvent) {
        save.saveLocal(game);
        save.upload(game);
        social?.syncProfile(game);
      }
    });
  }

  /// 친구 선물함 · 공지 확인, 공개 프로필 갱신 (실패해도 조용히, 모두 시간 제한).
  void _refreshSocial({bool force = false}) {
    final s = social;
    if (s == null || !auth.signedIn) return;
    unawaited(s.refresh(game, force: force));
  }

  // ---------------------------------------------------------------- 로그인 ↔ 저장

  Future<void> _onAuthChanged() async {
    final uid = auth.uid;
    if (!mounted) return;
    setState(() {});
    if (uid == null || uid == _attachedUid || _attaching) return;
    _attaching = true;
    try {
      await save.attach(
        uid,
        game,
        askUser: (local, cloud) async {
          final ctx = _navKey.currentContext;
          if (ctx == null) return true;
          return askSaveConflict(ctx, local, cloud);
        },
      );
      _attachedUid = uid;
      _refreshSocial(force: true);
    } finally {
      _attaching = false;
    }
  }

  void _resetGame() {
    _gameSub?.cancel();
    setState(() {
      game = GameState()..adFree = widget.billing.adFree;
      _bindGame();
    });
  }

  // ---------------------------------------------------------------- 게임 루프

  void _start() {
    _lastTick = DateTime.now();
    _loop?.cancel();
    _loop = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now();
      final dt = now.difference(_lastTick).inMicroseconds / 1e6;
      _lastTick = now;
      if (auth.signedIn) game.tick(dt.clamp(0, 1)); // 긴 공백은 오프라인 보상으로 처리
    });
    _autosave?.cancel();
    _autosave = Timer.periodic(const Duration(seconds: 5), (_) {
      if (auth.signedIn) {
        save.saveLocal(game);
        DevLog.instance.maybeTick(game);
      }
    });
  }

  void _stop() {
    _loop?.cancel();
    _autosave?.cancel();
    if (auth.signedIn) {
      save.saveLocal(game);
      save.upload(game);
      social?.syncProfile(game);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stop();
      AudioService.instance.pauseMusic();
      DevLog.instance.record(game, 'pause');
    } else if (state == AppLifecycleState.resumed) {
      _start();
      AudioService.instance.resumeMusic();
      DevLog.instance.record(game, 'start');
      _offerOffline();
      _refreshSocial();
    }
  }

  Future<void> _offerOffline() async {
    if (!auth.signedIn) return;
    final reward = game.computeOffline();
    final ctx = _navKey.currentContext;
    if (reward == null || ctx == null) return;
    final adFree = widget.billing.adFree;
    final doubled = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (ctx) => GameDialog(
        banner: 'gold',
        title: IconText(
          tr('offline.hello.${Random().nextInt(3)}'),
          textAlign: TextAlign.center,
        ),
        content: PopupHero(
          art: ArtImage(Art.icon('moon'), size: 76),
          big: '[[coin]]${fmt(reward.coins)}',
          note: tr('offline.time', {'time': fmtDuration(reward.away)}),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: IconText(
              tr('offline.take'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(backgroundColor: Palette.ad),
              'button_purple',
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: IconText(
              adFree
                  ? tr('offline.double')
                  : tr('ctrl.ad', {'label': tr('offline.double')}),
            ),
          ),
        ],
      ),
    );
    var x2 = false;
    if (doubled == true) x2 = await widget.ads.showRewarded();
    game.grantOffline(reward, doubled: x2);
    save.saveLocal(game);
  }

  // ---------------------------------------------------------------- 설정 / 계정

  void _snack(String code) {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: IconText(
          tr(
            code == 'already_linked'
                ? 'account.alreadyLinked'
                : 'account.error',
          ),
        ),
      ),
    );
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on AuthException catch (e) {
      if (e.code != 'cancelled') _snack(e.code);
    }
  }

  Future<void> _signOut(BuildContext sheetCtx) async {
    Navigator.of(sheetCtx).pop();
    await save.upload(game);
    await _guard(auth.signOut);
    save.detach();
    await save.clearLocal();
    _attachedUid = null;
    _resetGame();
  }

  Future<void> _deleteAccount(BuildContext sheetCtx) async {
    final ok = await showDialog<bool>(
      context: sheetCtx,
      builder: (ctx) => GameDialog(
        content: IconText(tr('account.deleteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: IconText(tr('common.cancel')),
          ),
          FilledButton(
            style: plainButton(
              FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: IconText(tr('account.deleteYes')),
          ),
        ],
      ),
    );
    if (ok != true || !sheetCtx.mounted) return;
    Navigator.of(sheetCtx).pop();
    await _guard(auth.deleteAccount);
    save.detach();
    await save.clearLocal();
    _attachedUid = null;
    _resetGame();
  }

  void _openSettings(BuildContext context) {
    showSettingsSheet(
      context,
      listen: Listenable.merge([auth, save]),
      version: widget.version,
      game: game,
      accountSection: () => Builder(
        builder: (sheetCtx) => AccountSection(
          auth: auth,
          save: save,
          onLinkGoogle: () => _guard(auth.signInGoogle),
          onLinkKakao: () => _guard(auth.signInKakao),
          onSignOut: () => _signOut(sheetCtx),
          onDelete: () => _deleteAccount(sheetCtx),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    auth.removeListener(_onAuthChanged);
    _gameSub?.cancel();
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([L10n.instance, auth]),
      builder: (context, _) => MaterialApp(
        navigatorKey: _navKey,
        onGenerateTitle: (_) => tr('app.title'),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: L10n.instance.locale,
        supportedLocales: [for (final c in L10n.supported.keys) Locale(c)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: !auth.ready
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : !auth.signedIn
            ? LoginScreen(auth: auth, onError: _snack)
            : HomeScreen(
                key: ObjectKey(game),
                game: game,
                ads: widget.ads,
                billing: widget.billing,
                openSettings: _openSettings,
                extraListenable: _homeListen,
                openFriends: social != null && social!.enabled
                    ? (ctx) => showFriendsSheet(ctx, social!, game)
                    : null,
                socialBadge: () => social?.badge ?? false,
              ),
      ),
    );
  }
}
