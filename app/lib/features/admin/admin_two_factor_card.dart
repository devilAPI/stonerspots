import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../core/back_or_home.dart';
import '../../core/glass.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'admin_code_dialog.dart';
import 'admin_two_factor.dart';

/// Where the app sends admins who must set up 2FA first.
const kAdminTwoFactorPath = '/admin/2fa';

/// The 2FA card on a page of its own (for `totp_setup_required`).
class AdminTwoFactorScreen extends StatelessWidget {
  const AdminTwoFactorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: GlassAppBar(
        leading: const BackOrHomeButton(),
        title: Text(AppLocalizations.of(context).adminTitle),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12 + gutter, 12, 12 + gutter, 24),
        children: const [AdminTwoFactorCard()],
      ),
    );
  }
}

/// Status of the admin's own 2FA, with its setup (secret, QR code, first
/// code) and turning it off (password and code).
class AdminTwoFactorCard extends ConsumerStatefulWidget {
  const AdminTwoFactorCard({super.key});

  @override
  ConsumerState<AdminTwoFactorCard> createState() => _AdminTwoFactorCardState();
}

class _AdminTwoFactorCardState extends ConsumerState<AdminTwoFactorCard> {
  bool? _enabled;
  bool _loadFailed = false;
  TwoFactorEnrollment? _enrollment;
  bool _busy = false;
  String? _error;

  /// Just turned on: says what changes now.
  bool _justEnabled = false;
  final _code = TextEditingController();

  TwoFactorRepository get _repo => ref.read(twoFactorRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final on = await _repo.enabled();
      if (mounted) setState(() => _enabled = on);
    } on ApiException catch (e) {
      if (!mounted) return;
      // The status itself wants proof only when 2FA is on.
      final on = e.code == 'totp_required' || e.code == 'totp_session_expired';
      setState(() {
        _enabled = on ? true : _enabled;
        _loadFailed = !on;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = twoFactorErrorText(l, e));
      if (e is ApiException && e.code == 'already_enabled') {
        _enrollment = null;
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run(() async {
    final enrollment = await _repo.start();
    if (!mounted) return;
    _code.clear();
    setState(() {
      _enrollment = enrollment;
      _justEnabled = false;
    });
  });

  Future<void> _verify() async {
    final l = AppLocalizations.of(context);
    if (_code.text.length != 6) {
      setState(() => _error = l.twoFactorErrDigits);
      return;
    }
    await _run(() async {
      await _repo.verify(_code.text);
      if (!mounted) return;
      setState(() {
        _enrollment = null;
        _enabled = true;
        _justEnabled = true;
      });
    });
  }

  void _cancelSetup() => setState(() {
    _enrollment = null;
    _error = null;
  });

  Future<void> _disable() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final off = await showDialog<bool>(
      context: context,
      builder: (_) => const _DisableTwoFactorDialog(),
    );
    if (off != true || !mounted) return;
    setState(() {
      _enabled = false;
      _justEnabled = false;
      _error = null;
    });
    messenger.showSnackBar(SnackBar(content: Text(l.twoFactorDisabled)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final enabled = _enabled;
    final enrollment = _enrollment;

    final Widget body;
    if (enabled == null) {
      body = _loadFailed
          ? Row(
              children: [
                Expanded(child: Text(l.errorGeneric)),
                TextButton(
                  key: const Key('totp-retry'),
                  onPressed: _load,
                  child: Text(l.retry),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator());
    } else if (enrollment != null) {
      body = _Enrollment(
        enrollment: enrollment,
        code: _code,
        busy: _busy,
        error: _error,
        onVerify: _verify,
        onCancel: _cancelSetup,
        onChanged: () => setState(() => _error = null),
      );
    } else if (enabled) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_justEnabled)
            Container(
              key: const Key('totp-enabled-info'),
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l.twoFactorEnabledInfo,
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            )
          else ...[
            Text(l.twoFactorActiveHint),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('totp-disable'),
              onPressed: _busy ? null : _disable,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(l.twoFactorDisable),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.twoFactorIntro),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('totp-enable'),
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.qr_code_2),
              label: Text(l.twoFactorEnable),
            ),
          ),
          if (_error != null) _ErrorLine(_error!),
        ],
      );
    }

    return Card(
      key: const Key('totp-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.twoFactorTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (enabled != null)
                  _StatusChip(on: enabled, key: const Key('totp-status')),
              ],
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        on ? Icons.check_circle : Icons.remove_circle_outline,
        color: on ? scheme.primary : scheme.onSurfaceVariant,
      ),
      label: Text(on ? l.twoFactorOn : l.twoFactorOff),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      text,
      key: const Key('totp-error'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

/// Setup: the secret as QR code and text, then the first code.
class _Enrollment extends StatelessWidget {
  const _Enrollment({
    required this.enrollment,
    required this.code,
    required this.busy,
    required this.error,
    required this.onVerify,
    required this.onCancel,
    required this.onChanged,
  });

  final TwoFactorEnrollment enrollment;
  final TextEditingController code;
  final bool busy;
  final String? error;
  final VoidCallback onVerify;
  final VoidCallback onCancel;
  final VoidCallback onChanged;

  /// The secret in groups of four, easier to type off.
  static String _grouped(String s) => [
    for (var i = 0; i < s.length; i += 4)
      s.substring(i, i + 4 > s.length ? s.length : i + 4),
  ].join(' ');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.twoFactorScan),
        const SizedBox(height: 12),
        if (enrollment.uri.isNotEmpty)
          Center(
            child: Container(
              // scanners need the dark-on-light QR code with a quiet zone
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                key: const Key('totp-qr'),
                data: enrollment.uri,
                size: 196,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(l.twoFactorSecret, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  _grouped(enrollment.secret),
                  key: const Key('totp-secret'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
              ),
              IconButton(
                key: const Key('totp-copy'),
                tooltip: l.twoFactorCopy,
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(
                    ClipboardData(text: enrollment.secret),
                  );
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.twoFactorCopied)),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(l.twoFactorEnterCode),
        const SizedBox(height: 12),
        TotpCodeField(
          key: const Key('totp-code'),
          controller: code,
          enabled: !busy,
          errorText: error,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onVerify(),
        ),
        const SizedBox(height: 12),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('totp-cancel'),
              onPressed: busy ? null : onCancel,
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const Key('totp-verify'),
              onPressed: busy ? null : onVerify,
              child: Text(l.twoFactorConfirm),
            ),
          ],
        ),
      ],
    );
  }
}

/// Password and a current code; pops true once 2FA is off.
class _DisableTwoFactorDialog extends ConsumerStatefulWidget {
  const _DisableTwoFactorDialog();

  @override
  ConsumerState<_DisableTwoFactorDialog> createState() =>
      _DisableTwoFactorDialogState();
}

class _DisableTwoFactorDialogState
    extends ConsumerState<_DisableTwoFactorDialog> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (_password.text.isEmpty) {
      setState(() => _error = l.fieldRequired);
      return;
    }
    if (_code.text.length != 6) {
      setState(() => _error = l.twoFactorErrDigits);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(twoFactorRepositoryProvider)
          .disable(password: _password.text, code: _code.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = twoFactorErrorText(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GlassDialog(
      title: Text(l.twoFactorDisable),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.twoFactorDisableText),
          const SizedBox(height: 16),
          TextField(
            key: const Key('totp-disable-password'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            decoration: InputDecoration(labelText: l.password),
          ),
          const SizedBox(height: 12),
          TotpCodeField(
            key: const Key('totp-disable-code'),
            controller: _code,
            enabled: !_busy,
            labelText: l.twoFactorCode,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) _ErrorLine(_error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('totp-disable-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l.twoFactorDisable),
        ),
      ],
    );
  }
}
