import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../i18n/l10n.dart';
import '../services/audio_service.dart';
import 'theme.dart';

/// 켜기 → ① 스플래시(실제 로딩) → ② 타이틀(눌러서 시작) → ③ 짧은 전환 → 게임.
/// [boot] 는 무거운 준비(로그인 확인 · 저장 · 원격 설정 · 소리)를 하며 진행도를 알리고, 다 되면 게임 화면을 돌려준다.
class StartApp extends StatefulWidget {
  const StartApp({super.key, required this.boot, this.version = ''});
  final Future<Widget> Function(void Function(double progress) report) boot;
  final String version;

  @override
  State<StartApp> createState() => _StartAppState();
}

enum _Stage { splash, title, enter, game }

class _StartAppState extends State<StartApp> {
  _Stage _stage = _Stage.splash;
  double _progress = 0;
  Widget? _game;
  int _tip = 0;

  @override
  void initState() {
    super.initState();
    _tip = Random().nextInt(_tipCount);
    _run();
  }

  Future<void> _run() async {
    final started = DateTime.now();
    final game = await widget.boot((p) {
      if (mounted) setState(() => _progress = p.clamp(0.0, 1.0));
    });
    // 너무 빨리 끝나도 로고는 잠깐 보이게 (깜빡 지나가지 않게)
    final shown = DateTime.now().difference(started);
    const minSplash = Duration(milliseconds: 1200);
    if (shown < minSplash) await Future.delayed(minSplash - shown);
    if (!mounted) return;
    setState(() {
      _game = game;
      _progress = 1;
      _stage = _Stage.title;
    });
  }

  void _start() {
    if (_stage != _Stage.title) return;
    sfx(Sfx.open);
    setState(() => _stage = _Stage.enter);
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _stage = _Stage.game);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.game && _game != null) return _game!;
    return ListenableBuilder(
      listenable: L10n.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          child: switch (_stage) {
            _Stage.splash => SplashView(
              key: const ValueKey('splash'),
              progress: _progress,
            ),
            _Stage.title => TitleView(
              key: const ValueKey('title'),
              version: widget.version,
              onStart: _start,
            ),
            _ => EnterView(key: const ValueKey('enter'), tip: _tip),
          },
        ),
      ),
    );
  }
}

const int _tipCount = 6;

// ---------------------------------------------------------------- 로고

/// 타이틀 로고: 발주한 로고 그림(언어별)이 있으면 그것, 없으면 Jua 글꼴 + 갈색 외곽선 글자.
class TitleLogo extends StatelessWidget {
  const TitleLogo({super.key, this.width = 320});
  final double width;

  @override
  Widget build(BuildContext context) {
    final lang = L10n.instance.lang;
    final art = ArtRef('assets/art/title/logo_$lang.webp', '');
    final ko = const ArtRef('assets/art/title/logo_ko.webp', '');
    final pick = art.available
        ? art
        : (lang == 'ko' && ko.available ? ko : null);
    if (pick != null) {
      return Image.asset(pick.path, width: width, fit: BoxFit.contain);
    }
    final name = tr('app.title');
    final size = width / max(5.5, name.length * 0.95);
    TextStyle s(Paint? fg, Color? c) => TextStyle(
      fontFamily: 'Jua',
      fontSize: size,
      height: 1.1,
      foreground: fg,
      color: c,
    );
    return SizedBox(
      width: width,
      child: FittedBox(
        child: Stack(
          children: [
            Text(
              name,
              style: s(
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = size * 0.16
                  ..strokeJoin = StrokeJoin.round
                  ..color = const Color(0xFF5A3A1E),
                null,
              ),
            ),
            Text(name, style: s(null, const Color(0xFF7BC98F))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- ① 스플래시

class SplashView extends StatefulWidget {
  const SplashView({super.key, required this.progress});
  final double progress;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDF2E6),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _bob,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -10 * sin(_bob.value * pi)),
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Image.asset(
                  'assets/art/title/app_icon.webp',
                  width: 150,
                  height: 150,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const TitleLogo(width: 260),
            const SizedBox(height: 36),
            Container(
              width: 220,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF7A5230), width: 3),
              ),
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 300),
                widthFactor: max(0.04, widget.progress),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF7BC98F),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              tr('start.loading'),
              style: const TextStyle(fontSize: 15, color: Color(0xFF6E7C62)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- ② 타이틀

/// 요소가 차례로 통통 튀며 나온다: 배경 → 전경 덤불 → 로고 → 주인공(친구들) → "눌러서 시작".
class TitleView extends StatefulWidget {
  const TitleView({super.key, required this.onStart, this.version = ''});
  final VoidCallback onStart;
  final String version;

  @override
  State<TitleView> createState() => _TitleViewState();
}

class _TitleViewState extends State<TitleView> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// 구간 [a, b] (전체 0~1) 안에서 통통 튀는 0→1 값.
  double _pop(double a, double b) {
    final t = ((_intro.value - a) / (b - a)).clamp(0.0, 1.0);
    return Curves.elasticOut.transform(t);
  }

  double _fade(double a, double b) =>
      Curves.easeOut.transform(((_intro.value - a) / (b - a)).clamp(0.0, 1.0));

  void _tap() {
    // 연출 중에 누르면 먼저 연출을 끝까지 보여 준다
    if (_intro.value < 1) {
      _intro.value = 1;
      return;
    }
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    const bg = ArtRef('assets/art/title/bg.webp', '');
    const fg = ArtRef('assets/art/title/fg.webp', '');
    const hero = ArtRef('assets/art/title/hero.webp', '');
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth, h = c.maxHeight;
            return AnimatedBuilder(
              animation: Listenable.merge([_intro, _loop]),
              builder: (context, _) {
                final sway = sin(_loop.value * 2 * pi);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. 배경 (천천히 밝아지며 살짝 확대 → 제자리)
                    Opacity(
                      opacity: _fade(0, 0.18),
                      child: Transform.scale(
                        scale: 1.08 - 0.08 * _fade(0, 0.35),
                        child: bg.available
                            ? Image.asset(bg.path, fit: BoxFit.cover)
                            : Image.asset(
                                'assets/art/areas/yard_bg.webp',
                                fit: BoxFit.cover,
                                alignment: const Alignment(0.15, 0),
                              ),
                      ),
                    ),
                    // 하늘 쪽을 조금 밝게 (로고가 잘 보이게)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment(0, -0.1),
                          colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)],
                        ),
                      ),
                    ),
                    // 2. 로고 (위에서 떨어져 통통)
                    Positioned(
                      top: h * 0.11 - (1 - _pop(0.15, 0.5)) * h * 0.3,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Transform.rotate(
                          angle: sway * 0.015,
                          child: TitleLogo(width: min(w * 0.86, 420)),
                        ),
                      ),
                    ),
                    // 3. 주인공 (아래에서 쏙, 통통)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: h * 0.2,
                      height: h * 0.34,
                      child: hero.available
                          ? Transform.scale(
                              scale: _pop(0.4, 0.75),
                              alignment: Alignment.bottomCenter,
                              child: Image.asset(
                                hero.path,
                                fit: BoxFit.contain,
                              ),
                            )
                          : _HeroGroup(pop: _pop, sway: sway, width: w),
                    ),
                    // 4. 전경 덤불 (아래에서 올라옴)
                    if (fg.available)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: -h * 0.12 * (1 - _fade(0.3, 0.55)),
                        child: Image.asset(fg.path, fit: BoxFit.fitWidth),
                      ),
                    // 5. 눌러서 시작 (마지막에 톡, 그다음 숨쉬듯 깜빡)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: h * 0.12,
                      child: Center(
                        child: Transform.scale(
                          scale:
                              _pop(0.75, 1.0) *
                              (_intro.value >= 1 ? 1 + 0.04 * sway : 1),
                          child: Opacity(
                            opacity: _intro.value >= 1
                                ? 0.75 + 0.25 * sway.abs()
                                : 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xD93A6B45),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: Text(
                                tr('start.tap'),
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.version.isNotEmpty)
                      Positioned(
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                        left: 0,
                        right: 0,
                        child: Opacity(
                          opacity: _fade(0.8, 1),
                          child: Text(
                            'v${widget.version}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Color(0x88000000), blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 주인공 그림이 오기 전: 민트를 가운데에 두고 친구 넷이 한 명씩 통통 튀어나온다.
class _HeroGroup extends StatelessWidget {
  const _HeroGroup({
    required this.pop,
    required this.sway,
    required this.width,
  });
  final double Function(double a, double b) pop;
  final double sway;
  final double width;

  @override
  Widget build(BuildContext context) {
    final s = min(width * 0.3, 150.0);
    final cast = <(String, String, double, double, double)>[
      // id, 자세, x(가운데 기준 비율), 아래 여백 비율, 나오는 시점
      ('dubu', 'happy', -0.34, 0.28, 0.42),
      ('kwak', 'happy', 0.34, 0.3, 0.48),
      ('nabi', 'wave', -0.2, 0.0, 0.54),
      ('mochi', 'happy', 0.2, 0.02, 0.6),
      ('bori', 'wave', 0, 0.12, 0.66),
    ];
    return LayoutBuilder(
      builder: (context, c) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (id, pose, x, b, at) in cast)
            Positioned(
              left:
                  c.maxWidth / 2 +
                  x * c.maxWidth -
                  (id == 'bori' ? s * 0.6 : s * 0.5),
              bottom: b * c.maxHeight,
              child: Transform.scale(
                scale: pop(at, at + 0.3),
                alignment: Alignment.bottomCenter,
                child: Transform.rotate(
                  angle: (id == 'bori' ? 0 : sway * 0.04),
                  alignment: Alignment.bottomCenter,
                  child: ArtImage(
                    Art.friendPose(Friends.byId(id), pose) ??
                        Art.friend(Friends.byId(id), happy: true),
                    size: id == 'bori' ? s * 1.2 : s,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- ③ 정원으로 들어가기

class EnterView extends StatefulWidget {
  const EnterView({super.key, required this.tip});
  final int tip;

  @override
  State<EnterView> createState() => _EnterViewState();
}

class _EnterViewState extends State<EnterView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat();

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF7BC98F),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _hop,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -18 * sin(_hop.value * pi)),
                child: child,
              ),
              child: ArtImage(
                Art.friend(Friends.byId('kongtteok'), happy: true),
                size: 140,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              tr('start.entering'),
              style: const TextStyle(
                fontSize: 26,
                color: Colors.white,
                shadows: [
                  Shadow(color: Color(0xFF3A6B45), offset: Offset(0, 3)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF0),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF7A5230), width: 3),
              ),
              child: Column(
                children: [
                  Text(
                    tr('start.tipTitle'),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF7A5230),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('start.tip.${widget.tip}'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.45,
                      color: Palette.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
