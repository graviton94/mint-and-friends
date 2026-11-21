import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../i18n/l10n.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/save_service.dart';
import 'start_screens.dart' show TitleLogo;
import 'theme.dart';
import 'widgets/icon_text.dart';
import 'widgets/frame_box.dart';

/// 첫 실행 로그인 화면: 카카오 / Google / 게스트.
///
/// 버튼은 각 회사의 공식 가이드를 따른다:
/// - 카카오: 배경 #FEE500, 검은 말풍선 심볼, 글자 85% 검정, 둥근 모서리 12 (카카오 로그인 디자인 가이드)
/// - Google: 흰 배경, #747775 테두리, 공식 G 로고, 글자 #1F1F1F (Google 로그인 브랜딩 가이드)
/// 실패하면 화면 안에 이유를 짧게 보여 준다 (어느 쪽이 거절했고 코드가 무엇인지).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onError});
  final AuthService auth;
  final void Function(String code) onError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _pending; // 누른 버튼 (그 버튼에만 로딩 표시)
  String? _error;
  String? _detail;

  AuthService get auth => widget.auth;

  Future<void> _go(String which, Future<void> Function() f) async {
    sfx(Sfx.tap);
    setState(() {
      _pending = which;
      _error = null;
      _detail = null;
    });
    try {
      await f();
    } on AuthException catch (e) {
      if (e.code != 'cancelled' && mounted) {
        sfx(Sfx.error);
        setState(() {
          _error = tr(e.code == 'timeout' ? 'login.timeout' : 'login.failed');
          _detail = e.detail.isEmpty ? null : e.detail;
        });
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = ArtRef('assets/art/title/bg.webp', '');
    const fg = ArtRef('assets/art/title/fg.webp', '');
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([auth, L10n.instance]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) => Stack(
            fit: StackFit.expand,
            children: [
              // 타이틀 화면과 같은 그림: 배경 · 앞 덤불 (로그인도 게임의 첫인상)
              Image.asset(
                bg.available ? bg.path : 'assets/art/areas/yard_bg.webp',
                fit: BoxFit.cover,
              ),
              if (fg.available)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Image.asset(fg.path, fit: BoxFit.fitWidth),
                ),
              SafeArea(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 60),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: c.maxHeight * 0.05),
                          Center(
                            child: TitleLogo(
                              width: min(340, c.maxWidth * 0.82),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // 친구들 (바닥선에 나란히)
                          SizedBox(
                            height: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final f in Friends.all.take(4))
                                  ArtImage(Art.friend(f), size: 78),
                              ],
                            ),
                          ),
                          SizedBox(height: c.maxHeight * 0.04),
                          // 로그인 패널: 크림색 카드 + 갈색 테두리 (게임 창과 같은 모양)
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                            decoration: BoxDecoration(
                              color: const Color(0xF2FFF8EA),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFF7A5230),
                                width: 3,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 14,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                IconText(
                                  tr('login.subtitle'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF6B5A44),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (auth.kakaoEnabled) ...[
                                  _BrandButton(
                                    label: tr('login.kakao'),
                                    background: const Color(0xFFFEE500),
                                    foreground: const Color(0xD9000000),
                                    logo: 'assets/art/brand/kakao_symbol.png',
                                    busy: _pending == 'kakao',
                                    onTap: _pending != null
                                        ? null
                                        : () => _go('kakao', auth.signInKakao),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (auth.googleEnabled) ...[
                                  _BrandButton(
                                    label: tr('login.google'),
                                    background: Colors.white,
                                    foreground: const Color(0xFF1F1F1F),
                                    border: const Color(0xFF747775),
                                    logo: 'assets/art/brand/google_g.png',
                                    busy: _pending == 'google',
                                    onTap: _pending != null
                                        ? null
                                        : () =>
                                              _go('google', auth.signInGoogle),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                SizedBox(
                                  height: 52,
                                  child: FilledButton(
                                    style: framedButton(
                                      FilledButton.styleFrom(
                                        backgroundColor: Palette.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      'button_green',
                                    ),
                                    onPressed: _pending != null
                                        ? null
                                        : () => _go('guest', auth.signInGuest),
                                    child: _pending == 'guest'
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            tr('login.guest'),
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                  ),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFEDE6),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE07A5F),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        IconText(
                                          _error!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF9A3B22),
                                          ),
                                        ),
                                        if (_detail != null)
                                          SelectableText(
                                            _detail!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black45,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                IconText(
                                  tr('login.guestNote'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: Wrap(
                                    spacing: 6,
                                    children: [
                                      for (final e in L10n.supported.entries)
                                        TextButton(
                                          onPressed: () =>
                                              L10n.instance.setLanguage(e.key),
                                          child: Text(
                                            e.value,
                                            style: TextStyle(
                                              color: L10n.instance.lang == e.key
                                                  ? Palette.primary
                                                  : Colors.black45,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 공식 가이드 모양의 로그인 버튼 (로고 왼쪽 고정, 글자 가운데).
class _BrandButton extends StatelessWidget {
  const _BrandButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.logo,
    required this.busy,
    required this.onTap,
    this.border,
  });
  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final String logo;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border == null ? BorderSide.none : BorderSide(color: border!),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 18,
                child: Image.asset(
                  logo,
                  width: 22,
                  height: 22,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: foreground,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        color: foreground,
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.auth,
    required this.save,
    required this.onLinkGoogle,
    required this.onLinkKakao,
    required this.onSignOut,
    required this.onDelete,
  });
  final AuthService auth;
  final SaveService save;
  final VoidCallback onLinkGoogle;
  final VoidCallback onLinkKakao;
  final VoidCallback onSignOut;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([auth, save]),
      builder: (context, _) {
        final p = auth.provider;
        final status = switch (save.status) {
          SyncStatus.local => tr('account.offline'),
          SyncStatus.syncing => tr('account.syncing'),
          SyncStatus.synced => tr('account.synced', {
            'time': _hm(save.lastCloudSave),
          }),
          SyncStatus.error => tr('account.offline'),
        };
        return Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  p == LoginProvider.guest
                      ? tr('account.guest')
                      : tr('account.signedIn', {
                          'provider': tr('account.provider.${p.name}'),
                        }),
                  style: const TextStyle(fontSize: 17),
                ),
                Text(
                  status,
                  style: const TextStyle(fontSize: 13, color: Colors.black45),
                ),
                if (p == LoginProvider.guest &&
                    (auth.googleEnabled || auth.kakaoEnabled)) ...[
                  const SizedBox(height: 8),
                  IconText(
                    tr('account.linkHint'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  if (auth.kakaoEnabled)
                    OutlinedButton(
                      onPressed: auth.busy ? null : onLinkKakao,
                      child: IconText('[[kakao]] ${tr('account.linkKakao')}'),
                    ),
                  if (auth.googleEnabled)
                    OutlinedButton(
                      onPressed: auth.busy ? null : onLinkGoogle,
                      child: IconText('[[google]] ${tr('account.linkGoogle')}'),
                    ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: auth.busy ? null : onSignOut,
                        child: IconText(tr('account.logout')),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: auth.busy ? null : onDelete,
                        child: IconText(
                          tr('account.delete'),
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _hm(DateTime? t) => t == null
      ? ''
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 기기/클라우드 저장이 다를 때 고르는 창. true = 클라우드.
Future<bool> askSaveConflict(
  BuildContext context,
  SaveSummary local,
  SaveSummary cloud,
) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => GameDialog(
      title: IconText(tr('conflict.title'), textAlign: TextAlign.center),
      content: IconText(tr('conflict.body'), textAlign: TextAlign.center),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: IconText(
            tr('conflict.local', {'lv': local.level, 'area': local.area + 1}),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: IconText(
            tr('conflict.cloud', {'lv': cloud.level, 'area': cloud.area + 1}),
          ),
        ),
      ],
    ),
  );
  return r ?? true;
}
