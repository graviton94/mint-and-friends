import 'dart:math';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'art/art.dart';
import 'ui/widgets/reward_popup.dart';
import 'game/config.dart' show Starter, Offers, EnergyBundle, MilestoneBundle;
import 'game/format.dart';
import 'game/game_state.dart';
import 'i18n/l10n.dart';
import 'i18n/names.dart';
import 'services/ads_service.dart';
import 'services/audio_service.dart';
import 'services/notify_service.dart';
import 'services/auth_service.dart';
import 'services/billing_service.dart';
import 'services/invite_referrer.dart';
import 'services/purchase_guard.dart';
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
import 'services/crash_service.dart';
import 'services/remote_tuning.dart';
import 'services/dev_log.dart';
import 'services/update_service.dart';
import 'ui/share_flow.dart';
import 'ui/update_ui.dart';
import 'ui/start_screens.dart';
import 'ui/widgets/top_toast.dart';
import 'ui/widgets/spend_float.dart';

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
  // 서로 기다릴 필요 없는 준비는 한꺼번에 (D-108: 예전엔 하나씩 차례로 기다렸다).
  // 경제 변수 원격 조정은 오래 걸리면 기본값으로 시작
  var done = 0;
  void step() => report(0.35 + 0.4 * (++done) / 5);
  await Future.wait([
    RemoteTuning.load()
        .timeout(const Duration(seconds: 3), onTimeout: () {})
        .whenComplete(step),
    AudioService.instance.init().whenComplete(step),
    NotifyService.instance.init().whenComplete(step),
    Analytics.instance.checkTestDevice().whenComplete(step),
    DevLog.instance.init().whenComplete(step),
  ]);

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
  // 광고 없이 보상: 구독(adFree) 또는 기간제 정원 패스 (새싹 정원 패키지)
  final ads = AdsService(
    isAdFree: () => billing.adFree || (GameState.active?.passActive ?? false),
  );

  String version = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version} (${info.buildNumber})';
  } catch (_) {}
  // 비정상 종료 · 오류 수집 (Firebase 준비 뒤, 디버그 빌드는 끔)
  await CrashService.install(version: version);
  // Firebase 를 켜지 못했으면 기록 (다음에 연결될 때 함께 보낸다), 모아 둔 문제 보내기
  if (auth.initErrors.isNotEmpty) {
    unawaited(
      CrashService.issue('firebase_init', {
        'errors': auth.initErrors.join(' / '),
        'version': version,
      }),
    );
  }
  unawaited(CrashService.flushPending());

  unawaited(billing.init());
  unawaited(ads.init());
  // 진단 빌드: 공유를 단계별로 실행해 로그로 (share-probe.yml, 화면을 누르지 않아도 돈다)
  if (const bool.fromEnvironment('SHARE_PROBE')) {
    Future.delayed(const Duration(seconds: 6), () => runShareProbe(game));
  }
  // 진단 빌드: 알림 권한 · 즉시 알림 · 예약 알림을 단계별로 (notify-probe.yml)
  if (const bool.fromEnvironment('NOTIFY_PROBE')) {
    Future.delayed(const Duration(seconds: 6), () {
      debugPrint(
        'NOTIFYPROBE firebase apps=${Firebase.apps.length} authErrors=${auth.initErrors} '
        'google=${auth.googleEnabled} kakao=${auth.kakaoEnabled}',
      );
      NotifyService.instance.probe(game);
    });
  }
  // 초대 링크로 설치했으면 친구 코드를 받아 둔다 (첫 실행 한 번, D-045)
  unawaited(InviteReferrer.capture(prefs));
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
    GameState.active = game;
    _bindGame();
    // 자랑 카드에 넣는 내 친구 코드 · 정원 이름 (친구 기능을 쓸 수 있을 때만)
    ShareInfo.code = () => social?.canUse == true ? social?.me?.code : null;
    ShareInfo.name = () => social?.canUse == true ? social?.me?.name : null;
    WidgetsBinding.instance.addObserver(this);
    widget.billing.addListener(() => game.adFree = widget.billing.adFree);
    // 다이아 결제 → 지금 게임에 넣고 바로 저장 (계정 전환 뒤에도 현재 game 을 쓴다)
    widget.billing.onStarter = () {
      if (game.grantStarter()) {
        save.saveLocal(game);
        save.upload(game);
        _celebrate(
          const Reward(gems: Starter.gems, energy: Starter.energy),
          tr('reward.purchase'),
        );
      }
    };
    // 반복 환불 계정은 결제를 막는다 (D-068)
    widget.billing.blocked = () => game.purchaseBlocked;
    widget.billing.onBlocked = () {
      final ctx = _navKey.currentContext;
      if (ctx == null) return;
      showDialog<void>(
        context: ctx,
        builder: (c) => GameDialog(
          title: IconText(tr('refund.blockTitle'), textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArtImage(Art.mint('sorry'), size: 110),
              const SizedBox(height: 8),
              IconText(
                tr('refund.blockBody'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: IconText(tr('common.ok')),
            ),
          ],
        ),
      );
    };
    // 환불 확인용 결제 기록 (D-066)
    widget.billing.onRecord = (order, product) {
      final uid = auth.uid;
      if (uid != null) {
        unawaited(
          PurchaseGuard.instance.record(
            uid,
            order,
            product,
            game.lastPurchaseGems,
          ),
        );
      }
    };
    widget.billing.onGems = (pack) {
      final n = game.grantGemPack(pack);
      save.saveLocal(game);
      save.upload(game);
      _celebrate(Reward(gems: n), tr('reward.purchase'));
    };
    // 결제 묶음 (D-110): 저금통 · 에너지 묶음 · 단계 묶음
    widget.billing.onOffer = (id) {
      final Reward r;
      if (id == Offers.piggy) {
        r = Reward(gems: game.grantPiggy());
      } else if (id == Offers.eventPass) {
        game.grantEventPass();
        r = Reward(gems: game.lastPurchaseGems);
      } else if (id == Offers.energy) {
        game.grantEnergyBundle();
        r = const Reward(gems: EnergyBundle.gems, energy: EnergyBundle.energy);
      } else {
        final c = game.milestoneCoins;
        game.grantMilestone();
        r = Reward(
          gems: MilestoneBundle.gems,
          energy: MilestoneBundle.energy,
          coins: c.round(),
        );
      }
      save.saveLocal(game);
      save.upload(game);
      _celebrate(r, tr('reward.purchase'));
    };
    widget.billing.onAdFree = () => _celebrate(
      const Reward(),
      tr('reward.purchase'),
      art: Art.icon('no_ads'),
      sub: tr('reward.adFree'),
    );
    auth.addListener(_onAuthChanged);
    _start();
    DevLog.instance.record(game, 'start');
    // 새 버전으로 처음 열었으면 업데이트 안내 쪽지 (바뀐 점 + 작은 선물)
    final vName = widget.version.split(' ').first;
    if (game.addUpdateMail(_versionCode, vName)) save.saveLocal(game);
    // 새 버전 확인 (D-049): 게임 화면이 뜨고 조금 뒤, 다 받으면 '다시 열기' 창
    UpdateService.instance.addListener(_onUpdate);
    Future.delayed(const Duration(seconds: 4), _checkUpdate);
    // 알림 권한은 처음 한 번, 게임 화면이 뜬 뒤에 묻는다
    Future.delayed(const Duration(seconds: 6), NotifyService.instance.askOnce);
    NotifyService.instance.cancel();
    AudioService.instance.startMusic().then((_) {
      final a = AudioService.instance;
      DevLog.instance.note(
        'audio',
        '${a.status}${a.lastError == null ? '' : ' last=${a.lastError}'}',
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onAuthChanged();
      _offerOffline();
    });
  }

  /// 중요한 순간(레벨업, 장식, 구역 완성)에는 바로 클라우드에 올린다.
  // 재화가 줄면 누른 자리에서 '-[[star]]5' 가 떠오른다 (D-080). 재단장으로 비는 것은 빼고.
  double _seenCoins = 0, _seenStars = 0, _seenGems = 0;
  int _seenRenew = 0;
  void _watchSpend() {
    final ov = _navKey.currentState?.overlay;
    if (game.renewCount == _seenRenew && ov != null) {
      if (game.stars < _seenStars)
        SpendFloat.show(ov, 'star', _seenStars - game.stars);
      if (game.gems < _seenGems)
        SpendFloat.show(ov, 'diamond', _seenGems - game.gems);
      if (game.coins < _seenCoins - 0.5)
        SpendFloat.show(ov, 'coin', _seenCoins - game.coins);
    }
    _seenCoins = game.coins;
    _seenStars = game.stars.toDouble();
    _seenGems = game.gems.toDouble();
    _seenRenew = game.renewCount;
  }

  void _bindGame() {
    game.removeListener(_watchSpend);
    game.addListener(_watchSpend);
    _seenCoins = game.coins;
    _seenStars = game.stars.toDouble();
    _seenGems = game.gems.toDouble();
    _seenRenew = game.renewCount;
    Analytics.instance.attach(game);
    _gameSub?.cancel();
    _gameSub = game.events.listen((e) {
      if (e is LevelUpEvent) DevLog.instance.record(game, 'level');
      if (e is LevelUpEvent || e is AreaCompletedEvent) {
        CrashService.state(level: game.level, area: game.currentArea);
      }
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

  /// 이 앱의 버전 코드 (version 글자 '1.0.2 (1016)' 에서).
  int get _versionCode =>
      int.tryParse(
        RegExp(r'\((\d+)\)').firstMatch(widget.version)?.group(1) ?? '',
      ) ??
      0;

  Future<void> _checkUpdate() async {
    if (!mounted) return;
    final ask = await UpdateService.instance.check(myVersionCode: _versionCode);
    final ctx = _navKey.currentContext;
    if (ask == UpdateAsk.none || ctx == null || !ctx.mounted) return;
    await showUpdatePrompt(ctx, store: ask == UpdateAsk.store);
  }

  bool _readyShown = false;
  void _onUpdate() {
    if (UpdateService.instance.phase != UpdatePhase.downloaded || _readyShown) {
      return;
    }
    _readyShown = true;
    final ctx = _navKey.currentContext;
    if (ctx != null) showUpdateReady(ctx);
  }

  /// 친구 선물함 · 공지 확인, 공개 프로필 갱신 (실패해도 조용히, 모두 시간 제한).
  /// 환불된 결제를 되돌린다 (접속 · 다시 열 때, D-066).
  Future<void> _checkRefunds() async {
    final uid = auth.uid;
    if (uid == null || !auth.signedIn) return;
    final list = await PurchaseGuard.instance.pending(uid);
    if (list.isEmpty) return;
    var any = false;
    for (final (id, product, gems) in list) {
      if (game.revokePurchase(id, product, gems)) any = true;
    }
    await PurchaseGuard.instance.done(uid, [for (final x in list) x.$1]);
    if (!any) return;
    // 운영자가 알 수 있게 (반복 환불 확인용)
    CrashService.issue('refund_revoked', {
      'orders': '${list.length}',
      'total': '${game.revokedOrders.length}',
      'gems': '${game.gems}',
    });
    save.saveLocal(game);
    unawaited(save.upload(game));
    final ctx = _navKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await showDialog<void>(
        context: ctx,
        builder: (c) => GameDialog(
          title: IconText(tr('refund.title'), textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArtImage(Art.mint('sorry'), size: 110),
              const SizedBox(height: 8),
              IconText(
                tr(game.gems < 0 ? 'refund.bodyDebt' : 'refund.body', {
                  'n': -game.gems,
                }),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: IconText(tr('common.ok')),
            ),
          ],
        ),
      );
    }
  }

  void _refreshSocial({bool force = false}) {
    unawaited(_checkRefunds());
    final s = social;
    if (s == null || !auth.signedIn) return;
    unawaited(s.refresh(game, force: force).then((_) => _applyPendingInvite()));
  }

  /// 초대 링크로 설치한 새 계정: 받아 둔 친구 코드로 친구 맺기 + 환영 선물 (한 번).
  Future<void> _applyPendingInvite() async {
    final s = social;
    final prefs = widget.save.prefs;
    final code = InviteReferrer.pending(prefs);
    if (s == null || code == null || !s.canUse) return;
    if (!game.canBeInvited) {
      await InviteReferrer.clear(prefs);
      return;
    }
    try {
      if (await s.applyInvite(code, game)) {
        Analytics.instance.inviteApplied('referrer');
        widget.save.saveLocal(game);
        unawaited(widget.save.upload(game));
      }
      await InviteReferrer.clear(prefs);
    } on SocialException catch (e) {
      debugPrint('invite: ${e.code}'); // 다음 기회에 다시
    }
  }

  // ---------------------------------------------------------------- 로그인 ↔ 저장

  /// 직전에 게임 화면이었는지 (게스트 대기에서 돌아올 때 그동안의 방치 보상을 주려고).
  late bool _wasSignedIn = auth.signedIn;

  Future<void> _onAuthChanged() async {
    final uid = auth.uid;
    if (!mounted) return;
    final back = auth.signedIn && !_wasSignedIn;
    _wasSignedIn = auth.signedIn;
    // 첫 틱이 lastSeen 을 지금으로 당기기 전에 (동기 구간에서) 방치 보상을 계산한다
    if (back) _offerOffline();
    setState(() {});
    if (uid == null || uid == _attachedUid || _attaching) return;
    _attaching = true;
    var ok = false;
    try {
      ok = await save.attach(
        uid,
        game,
        askUser: (local, cloud) async {
          final ctx = _navKey.currentContext;
          if (ctx == null) return true;
          return askSaveConflict(ctx, local, cloud);
        },
      );
      if (ok) {
        _attachedUid = uid;
        _refreshSocial(force: true);
      }
    } finally {
      _attaching = false;
    }
    // 클라우드를 못 읽었으면 (연결 문제) 잠시 뒤 다시. 그동안은 기기에 저장된다.
    if (!ok) {
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && auth.uid == uid) _onAuthChanged();
      });
    }
  }

  void _resetGame() {
    _gameSub?.cancel();
    setState(() {
      game = GameState()..adFree = widget.billing.adFree;
      GameState.active = game;
      _bindGame();
    });
  }

  // ---------------------------------------------------------------- 게임 루프

  void _start() {
    // 월간 이벤트 '하루 세 번 들르기' (D-116)
    if (auth.signedIn) {
      game.noteVisit();
      // 하루 한 번 상태 기록 · 사용자 속성 (D-118)
      unawaited(Analytics.instance.dailySnapshot(game));
    }
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
      // 로그인 화면(게스트 대기 포함)에서는 게임 알림을 걸지 않는다
      if (auth.signedIn) NotifyService.instance.schedule(game);
    } else if (state == AppLifecycleState.resumed) {
      NotifyService.instance.cancel();
      _start();
      AudioService.instance.resumeMusic();
      DevLog.instance.record(game, 'start');
      _offerOffline();
      _refreshSocial();
      // 오래 켜 둔 앱도 새 버전을 알 수 있게 (30분에 한 번)
      // 원격 설정(최신 버전 코드 등)도 다시 받아 둔다 (Firebase 쪽에서 1시간에 한 번으로 제한)
      if (UpdateService.instance.checkDue) {
        RemoteTuning.load().whenComplete(
          () => Future.delayed(const Duration(seconds: 2), _checkUpdate),
        );
      }
    }
  }

  Future<void> _offerOffline() async {
    if (!auth.signedIn) return;
    final reward = game.computeOffline();
    final ctx = _navKey.currentContext;
    if (reward == null || ctx == null) return;
    final adFree = widget.billing.adFree;
    var adBusy = false;
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
          art: GlowHalo(child: ArtImage(Art.icon('moon'), size: 84)),
          big: '[[coin]]${fmt(reward.coins)}',
          note: tr('offline.time', {'time': fmtDuration(reward.away)}),
        ),
        actions: [
          DialogAdButton(
            label: tr('reward.times', {'n': 2}),
            sub: '[[coin]]${fmt(reward.coins * 2)}',
            adFree: adFree,
            onTap: () async {
              // 광고가 없으면 다른 보상 버튼처럼 알리고 창을 그대로 둔다 (보상을 쓰지 않는다)
              if (adBusy) return;
              adBusy = true;
              final ok = await widget.ads.showRewarded();
              adBusy = false;
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.pop(ctx, true);
              } else {
                TopToast.show(ctx, tr('toast.adLoading'));
                Analytics.instance.adUnavailable();
              }
            },
          ),
          DialogPlainButton(
            label: '${tr('offline.take')}  [[coin]]${fmt(reward.coins)}',
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    );
    final x2 = doubled == true; // 광고는 창 안에서 이미 봤다
    game.grantOffline(reward, doubled: x2);
    save.saveLocal(game);
    _celebrate(
      Reward(coins: (reward.coins * (x2 ? 2 : 1)).round()),
      tr(x2 ? 'reward.ad' : 'reward.offline'),
    );
  }

  /// 결제 · 광고 보상 축하 창 (결제는 화면 밖에서 끝나므로 맨 위 내비게이터에 띄운다).
  void _celebrate(Reward r, String title, {ArtRef? art, String? sub}) {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    RewardPopup.show(ctx, r, title: title, art: art, sub: sub);
  }

  // ---------------------------------------------------------------- 설정 / 계정

  void _snack(String code) {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    TopToast.show(
      ctx,
      tr(code == 'already_linked' ? 'account.alreadyLinked' : 'account.error'),
    );
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on AuthException catch (e) {
      if (e.code == 'cancelled') return;
      final ctx = _navKey.currentContext;
      if (e.code != 'already_linked' && ctx != null && ctx.mounted) {
        await showLoginFailed(ctx, auth, 'link', e);
      } else {
        _snack(e.code);
      }
    }
  }

  Future<void> _signOut(BuildContext sheetCtx) async {
    Navigator.of(sheetCtx).pop();
    if (auth.isGuest) {
      // 게스트: 계정 · 진행은 이 기기에 그대로 두고 로그인 화면으로만 (다시 게스트로 시작하면 이어서)
      save.saveLocal(game);
      await save.upload(game);
      // 대기 중에는 클라우드 자동 업로드를 멈추고, 다시 들어오면 새로 붙인다 (같은 계정이라 묻지 않음)
      save.detach();
      _attachedUid = null;
      await auth.parkGuest();
      return;
    }
    // 마지막 업로드가 실제로 끝났을 때만 기기 데이터를 지운다
    if (!await save.upload(game)) {
      final ctx = _navKey.currentContext;
      if (ctx != null && ctx.mounted) {
        TopToast.show(ctx, tr('account.logoutFailed'));
      }
      return;
    }
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
        // 업데이트 받는 중 · 다 받음 알약 (모든 화면 위)
        // 아무 곳이나 만지면 '손대는 중' (자동 정원 보너스는 1분 동안 안 만질 때만, D-059)
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          // 휴대폰 글자 크기를 아주 크게 해도 게임 화면이 겹치지 않게 1.15배까지만 (D-077)
          maxScaleFactor: 1.15,
          // 일본어 글꼴(Mochiy Pop)은 글자 폭이 넓어 같은 칸에서 줄이 더 자주 바뀐다: 조금 작게 (D-105)
          child: _JaTextScale(
            child: Stack(
              children: [
                if (child != null)
                  Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (d) {
                      game.noteInput();
                      SpendFloat.lastTap = d.position;
                    },
                    child: child,
                  ),
                UpdatePill(
                  onReadyTap: () {
                    final ctx = _navKey.currentContext;
                    if (ctx != null) showUpdateReady(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
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

/// 일본어일 때 글자 크기를 8% 줄인다 (D-105). 휴대폰 글자 크기 설정은 그대로 곱해진다.
class _JaTextScale extends StatelessWidget {
  const _JaTextScale({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (L10n.instance.lang != 'ja') return child;
    final base = MediaQuery.textScalerOf(context);
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(base.scale(100) / 100 * 0.92)),
      child: child,
    );
  }
}
