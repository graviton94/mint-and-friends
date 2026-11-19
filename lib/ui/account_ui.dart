import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../i18n/l10n.dart';
import '../services/auth_service.dart';
import '../services/save_service.dart';
import 'theme.dart';

/// 첫 실행 로그인 화면: 카카오 / Google / 게스트.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.auth, required this.onError});
  final AuthService auth;
  final void Function(String code) onError;

  Future<void> _go(Future<void> Function() f) async {
    try {
      await f();
    } on AuthException catch (e) {
      if (e.code != 'cancelled') onError(e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Palette.bgTop, Palette.bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([auth, L10n.instance]),
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final f in Friends.all.take(4))
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: ArtImage(Art.friend(f), size: 48),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('app.title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 40,
                      color: Palette.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('login.subtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const Spacer(flex: 3),
                  if (auth.kakaoEnabled)
                    _LoginButton(
                      label: tr('login.kakao'),
                      color: const Color(0xFFFEE500),
                      textColor: const Color(0xFF191600),
                      icon: '💬',
                      onTap: auth.busy ? null : () => _go(auth.signInKakao),
                    ),
                  if (auth.googleEnabled)
                    _LoginButton(
                      label: tr('login.google'),
                      color: Colors.white,
                      textColor: const Color(0xFF1F1F1F),
                      icon: 'G',
                      onTap: auth.busy ? null : () => _go(auth.signInGoogle),
                    ),
                  _LoginButton(
                    label: tr('login.guest'),
                    color: Palette.primary,
                    textColor: Colors.white,
                    icon: '🌱',
                    onTap: auth.busy ? null : () => _go(auth.signInGuest),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr('login.guestNote'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black45),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final e in L10n.supported.entries)
                          TextButton(
                            onPressed: () => L10n.instance.setLanguage(e.key),
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
                  if (auth.busy)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final Color color;
  final Color textColor;
  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 54,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: textColor,
            side: color == Colors.white
                ? const BorderSide(color: Color(0xFFDADCE0))
                : null,
          ),
          onPressed: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: TextStyle(fontSize: 20, color: textColor)),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 17, color: textColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 설정 시트의 계정 영역.
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
                  Text(
                    tr('account.linkHint'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  if (auth.kakaoEnabled)
                    OutlinedButton(
                      onPressed: auth.busy ? null : onLinkKakao,
                      child: Text('💬 ${tr('account.linkKakao')}'),
                    ),
                  if (auth.googleEnabled)
                    OutlinedButton(
                      onPressed: auth.busy ? null : onLinkGoogle,
                      child: Text('G  ${tr('account.linkGoogle')}'),
                    ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: auth.busy ? null : onSignOut,
                        child: Text(tr('account.logout')),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: auth.busy ? null : onDelete,
                        child: Text(
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
    builder: (ctx) => AlertDialog(
      title: Text(tr('conflict.title'), textAlign: TextAlign.center),
      content: Text(tr('conflict.body'), textAlign: TextAlign.center),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            tr('conflict.local', {'lv': local.level, 'area': local.area + 1}),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            tr('conflict.cloud', {'lv': cloud.level, 'area': cloud.area + 1}),
          ),
        ),
      ],
    ),
  );
  return r ?? true;
}
