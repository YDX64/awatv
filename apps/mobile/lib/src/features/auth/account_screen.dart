import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/auth/cloud_sync_gate.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Account dashboard for signed-in users.
///
/// Routed at `/account`, protected by `authGuard`. Shows the avatar +
/// name + email, a sync status row, an inline "edit display name"
/// affordance, and a danger zone (sign out, delete account).
///
/// The `Delete account` button does NOT actually destroy data — that
/// would need a server-side RPC. For now it surfaces a confirmation
/// dialog explaining the consequences and a `mailto:` so the user can
/// request deletion. Wiring the destructive call lives behind a server
/// migration we ship in Phase 6.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _editing = false;
  final _nameController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('auth.account_signout_dialog_title'.tr()),
        content: Text('auth.account_signout_dialog_body'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('auth.account_signout_action'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'auth.account_signout_failed'
                .tr(namedArgs: <String, String>{'message': e.toString()}),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).updateDisplayName(name);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'auth.account_save_failed'
                .tr(namedArgs: <String, String>{'message': e.toString()}),
          ),
        ),
      );
    }
  }

  Future<void> _showDeleteDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('auth.account_delete_dialog_title'.tr()),
        content: Text('auth.account_delete_dialog_body'.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final canCloud = ref.watch(canUseCloudSyncProvider);

    if (auth is! AuthSignedIn) {
      // The router guard should prevent this, but render a graceful
      // fallback in case the user signs out mid-screen.
      return Scaffold(
        appBar: AppBar(title: Text('auth.account_title'.tr())),
        body: Center(child: Text('auth.account_not_signed_in'.tr())),
      );
    }

    final theme = Theme.of(context);
    final displayName =
        auth.displayName ?? auth.email.split('@').first;

    return Scaffold(
      appBar: AppBar(title: Text('auth.account_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceL),
        children: <Widget>[
          Center(
            child: _AvatarTile(name: displayName, email: auth.email),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          _SectionHeader('auth.account_section_profile'.tr()),
          if (_editing)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceL,
                vertical: DesignTokens.spaceS,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      enabled: !_saving,
                      decoration: InputDecoration(
                        labelText: 'auth.account_field_display_name'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _saveName(),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceS),
                  IconButton(
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    onPressed: _saving ? null : _saveName,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _saving
                        ? null
                        : () => setState(() => _editing = false),
                  ),
                ],
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text('auth.account_field_display_name'.tr()),
              subtitle: Text(displayName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () {
                _nameController.text = auth.displayName ?? '';
                setState(() => _editing = true);
              },
            ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: Text('auth.account_field_email'.tr()),
            subtitle: Text(auth.email),
          ),
          const Divider(),
          _SectionHeader('auth.account_section_sync'.tr()),
          ListTile(
            leading: Icon(
              canCloud
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_outlined,
              color: canCloud ? BrandColors.success : null,
            ),
            title: Text(
              canCloud
                  ? 'auth.account_cloud_on'.tr()
                  : 'auth.account_cloud_off'.tr(),
            ),
            subtitle: Text(
              canCloud
                  ? 'auth.account_cloud_just_now'.tr()
                  : 'auth.account_cloud_upgrade'.tr(),
            ),
            trailing: canCloud
                ? null
                : TextButton(
                    onPressed: () => context.push('/premium'),
                    child: Text('auth.account_cloud_upgrade_action'.tr()),
                  ),
          ),
          const Divider(),
          _SectionHeader('auth.account_section_account'.tr()),
          ListTile(
            leading: Icon(
              Icons.logout_rounded,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'auth.account_signout_action'.tr(),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: _signOut,
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'auth.account_delete'.tr(),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: Text('auth.account_delete_subtitle'.tr()),
            onTap: _showDeleteDialog,
          ),
        ],
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({required this.name, required this.email});

  final String name;
  final String email;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.isEmpty ? '?' : p.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: BrandColors.brandGradient,
          ),
          child: Center(
            child: Text(
              _initials,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceM),
        Text(name, style: theme.textTheme.titleLarge),
        const SizedBox(height: DesignTokens.spaceXs),
        Text(
          email,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceL,
        DesignTokens.spaceL,
        DesignTokens.spaceL,
        DesignTokens.spaceXs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      ),
    );
  }
}
