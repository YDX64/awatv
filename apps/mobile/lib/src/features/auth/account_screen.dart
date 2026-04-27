import 'package:awatv_mobile/src/shared/auth/auth_controller.dart';
import 'package:awatv_mobile/src/shared/auth/auth_state.dart';
import 'package:awatv_mobile/src/shared/auth/cloud_sync_gate.dart';
import 'package:awatv_ui/awatv_ui.dart';
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
        title: const Text('Sign out?'),
        content: const Text(
          'You\'ll go back to local-only mode. Your on-device data stays.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
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
        SnackBar(content: Text('Sign-out failed: $e')),
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
        SnackBar(content: Text('Couldn\'t save: $e')),
      );
    }
  }

  Future<void> _showDeleteDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'Account deletion permanently removes your cloud-synced data. '
          'On-device playlists stay on this device.\n\n'
          'To request deletion, email support@awatv.app from your account '
          'address. We respond within 7 days.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
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
        appBar: AppBar(title: const Text('Account')),
        body: const Center(child: Text('Not signed in.')),
      );
    }

    final theme = Theme.of(context);
    final displayName =
        auth.displayName ?? auth.email.split('@').first;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceL),
        children: <Widget>[
          Center(
            child: _AvatarTile(name: displayName, email: auth.email),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          _SectionHeader('Profile'),
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
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        border: OutlineInputBorder(),
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
              title: const Text('Display name'),
              subtitle: Text(displayName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () {
                _nameController.text = auth.displayName ?? '';
                setState(() => _editing = true);
              },
            ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: const Text('Email'),
            subtitle: Text(auth.email),
          ),
          const Divider(),
          _SectionHeader('Sync'),
          ListTile(
            leading: Icon(
              canCloud
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_outlined,
              color: canCloud ? BrandColors.success : null,
            ),
            title: Text(
              canCloud ? 'Cloud sync is on' : 'Cloud sync (premium)',
            ),
            subtitle: Text(
              canCloud
                  ? 'Last sync: just now'
                  : 'Upgrade to premium to enable cross-device sync.',
            ),
            trailing: canCloud
                ? null
                : TextButton(
                    onPressed: () => context.push('/premium'),
                    child: const Text('Upgrade'),
                  ),
          ),
          const Divider(),
          _SectionHeader('Account'),
          ListTile(
            leading: Icon(
              Icons.logout_rounded,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'Sign out',
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
              'Delete account',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: const Text(
              'Email support to permanently remove your cloud data.',
            ),
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

