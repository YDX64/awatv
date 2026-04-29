import 'package:awatv_mobile/src/features/profiles/widgets/pin_entry_sheet.dart';
import 'package:awatv_mobile/src/features/profiles/widgets/profile_avatar.dart';
import 'package:awatv_mobile/src/shared/profiles/profile.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "Bu kim?" — the Netflix-style profile picker shown after login when
/// the device has 2+ profiles, and accessible any time from settings.
class ProfilePickerScreen extends ConsumerWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(profilesListProvider);
    final controller = ref.watch(profileControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil seç'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Yeni profil',
            onPressed: () => context.push('/profiles/edit'),
          ),
        ],
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: Text(
              'Profiller yüklenemedi: $e',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (List<UserProfile> profiles) {
          if (profiles.isEmpty) {
            return const _EmptyHelper();
          }
          return Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: GridView.count(
              crossAxisCount: _columnsForWidth(MediaQuery.of(context).size.width),
              crossAxisSpacing: DesignTokens.spaceM,
              mainAxisSpacing: DesignTokens.spaceM,
              children: <Widget>[
                for (final p in profiles)
                  _ProfileTile(
                    profile: p,
                    onTap: () => _handleSelect(context, ref, controller, p),
                    onLongPress: () =>
                        _handleLongPress(context, controller, p),
                  ),
                _AddProfileTile(
                  onTap: () => context.push('/profiles/edit'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static int _columnsForWidth(double width) {
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  Future<void> _handleSelect(
    BuildContext context,
    WidgetRef ref,
    ProfileController controller,
    UserProfile profile,
  ) async {
    String? pin;
    if (profile.requiresPin && profile.hasPin) {
      pin = await PinEntrySheet.show(
        context,
        title: profile.name,
        subtitle: 'Bu profile geçmek için PIN gir',
        validator: (String entered) =>
            controller.verifyPin(profile, entered) ? null : 'Yanlış PIN',
      );
      if (pin == null) return;
    }
    try {
      await controller.switchTo(profile.id, pin: pin);
      if (!context.mounted) return;
      context.go('/home');
    } on ProfilePinMismatchException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN doğrulanamadı.')),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profil değiştirilemedi: $e')),
      );
    }
  }

  Future<void> _handleLongPress(
    BuildContext context,
    ProfileController controller,
    UserProfile profile,
  ) async {
    final action = await showModalBottomSheet<_ProfileAction>(
      context: context,
      builder: (BuildContext sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Düzenle'),
              onTap: () =>
                  Navigator.of(sheetCtx).pop(_ProfileAction.edit),
            ),
            if (profile.id != _defaultProfileId)
              ListTile(
                leading: Icon(
                  Icons.delete_rounded,
                  color: Theme.of(sheetCtx).colorScheme.error,
                ),
                title: Text(
                  'Sil',
                  style: TextStyle(
                    color: Theme.of(sheetCtx).colorScheme.error,
                  ),
                ),
                onTap: () =>
                    Navigator.of(sheetCtx).pop(_ProfileAction.delete),
              ),
            const SizedBox(height: DesignTokens.spaceM),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _ProfileAction.edit:
        await context.push('/profiles/edit/${profile.id}');
      case _ProfileAction.delete:
        await _confirmAndDelete(context, controller, profile);
    }
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    ProfileController controller,
    UserProfile profile,
  ) async {
    if (profile.requiresPin && profile.hasPin) {
      final pin = await PinEntrySheet.show(
        context,
        title: 'Sil: ${profile.name}',
        subtitle: 'Profili silmek için mevcut PIN gerekli',
        validator: (String s) =>
            controller.verifyPin(profile, s) ? null : 'Yanlış PIN',
      );
      if (pin == null) return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogCtx) => AlertDialog(
        title: Text('${profile.name} silinsin mi?'),
        content: const Text(
          'Bu profilin favorileri ve izleme geçmişi kalıcı olarak '
          'silinecek. Diğer profiller etkilenmez.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteProfile(profile.id);
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    }
  }

  static String get _defaultProfileId =>
      ProfileController.defaultProfileSentinel;
}

enum _ProfileAction { edit, delete }

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.onTap,
    required this.onLongPress,
  });

  final UserProfile profile;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              children: <Widget>[
                ProfileAvatar(profile: profile, size: 96),
                if (profile.requiresPin && profile.hasPin)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(Icons.lock_rounded, size: 14),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (profile.isKids)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.tertiary.withValues(alpha: 0.18),
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusS),
                  ),
                  child: Text(
                    'ÇOCUK',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.tertiary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddProfileTile extends StatelessWidget {
  const _AddProfileTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.4),
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 36,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              'Yeni profil',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHelper extends StatelessWidget {
  const _EmptyHelper();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.people_outline, size: 64),
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              'Henüz profil yok',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: DesignTokens.spaceS),
            const Text(
              'Yeni profil oluşturarak izleme deneyimini kişiselleştirebilirsin.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
