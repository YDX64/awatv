import 'package:awatv_mobile/src/features/profiles/widgets/pin_entry_sheet.dart';
import 'package:awatv_mobile/src/features/profiles/widgets/profile_avatar.dart';
import 'package:awatv_mobile/src/shared/profiles/profile.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Create / edit a single user profile.
///
/// When [profileId] is `null` we create a new profile; otherwise we
/// hydrate the form from the current list and persist updates back to
/// Hive on save.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({this.profileId, super.key});

  final String? profileId;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

const List<String> _kAvatarEmojis = <String>[
  'TV', 'AB', 'AC', 'AD', '01', '02',
  // Symbol-style "emoji" — keeping it ASCII so font availability never
  // changes the result. Real emoji rendering is hardware-dependent on
  // Flutter desktop.
];

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String? _avatarEmoji;
  Color? _avatarColor;
  bool _isKids = false;
  bool _requiresPin = false;
  String? _newPin;
  bool _hadPin = false;
  bool _saving = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _hydrateIfNeeded(List<UserProfile> list) {
    if (_hydrated) return;
    final id = widget.profileId;
    if (id == null) {
      _avatarColor = kProfileAvatarPalette.first;
      _avatarEmoji = _kAvatarEmojis.first;
      _hydrated = true;
      return;
    }
    UserProfile? existing;
    for (final p in list) {
      if (p.id == id) {
        existing = p;
        break;
      }
    }
    if (existing == null) {
      _hydrated = true;
      return;
    }
    _nameCtrl.text = existing.name;
    _avatarEmoji = existing.avatarEmoji ?? _kAvatarEmojis.first;
    _avatarColor = existing.avatarColor;
    _isKids = existing.isKids;
    _requiresPin = existing.requiresPin;
    _hadPin = existing.hasPin;
    _hydrated = true;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(profileControllerProvider);
      // If the user just enabled PIN we collect it now; for an existing
      // profile with PIN the user can also pick "PIN'i değiştir" via
      // the explicit row we render below.
      var pinToSet = _newPin;
      if (_requiresPin && !_hadPin && pinToSet == null) {
        pinToSet = await PinEntrySheet.show(
          context,
          title: 'Yeni PIN',
          subtitle: '4-6 haneli bir PIN seç',
        );
        if (pinToSet == null) {
          setState(() {
            _saving = false;
            _requiresPin = false;
          });
          return;
        }
        // Confirm step.
        if (!mounted) return;
        final confirm = await PinEntrySheet.show(
          context,
          title: "PIN'i doğrula",
          subtitle: "Az önce girdiğin PIN'i tekrar gir",
          validator: (String s) => s == pinToSet ? null : 'PIN eşleşmiyor',
        );
        if (confirm == null) {
          setState(() {
            _saving = false;
            _requiresPin = false;
          });
          return;
        }
      }
      if (widget.profileId == null) {
        await controller.createProfile(
          name: _nameCtrl.text,
          avatarEmoji: _avatarEmoji,
          avatarColor: _avatarColor,
          isKids: _isKids,
          requiresPin: _requiresPin,
          pin: pinToSet,
        );
      } else {
        await controller.updateProfile(
          widget.profileId!,
          name: _nameCtrl.text,
          avatarEmoji: _avatarEmoji,
          avatarColor: _avatarColor,
          isKids: _isKids,
          requiresPin: _requiresPin,
          pin: pinToSet,
          clearPin: !_requiresPin && _hadPin,
        );
      }
      if (!mounted) return;
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePin() async {
    final controller = ref.read(profileControllerProvider);
    final list = ref.read(profilesListProvider).valueOrNull ??
        const <UserProfile>[];
    UserProfile? profile;
    for (final p in list) {
      if (p.id == widget.profileId) {
        profile = p;
        break;
      }
    }
    if (profile == null) return;

    if (profile.hasPin) {
      final old = await PinEntrySheet.show(
        context,
        title: 'Mevcut PIN',
        subtitle: "Önce eski PIN'i gir",
        validator: (String s) =>
            controller.verifyPin(profile!, s) ? null : 'Yanlış PIN',
      );
      if (old == null) return;
    }
    if (!mounted) return;
    final fresh = await PinEntrySheet.show(
      context,
      title: 'Yeni PIN',
      subtitle: '4-6 haneli yeni bir PIN seç',
    );
    if (fresh == null) return;
    if (!mounted) return;
    final confirmed = await PinEntrySheet.show(
      context,
      title: "PIN'i doğrula",
      subtitle: 'Tekrar gir',
      validator: (String s) => s == fresh ? null : 'PIN eşleşmiyor',
    );
    if (confirmed == null) return;
    await controller.setPin(profile.id, pin: fresh);
    if (!mounted) return;
    setState(() {
      _hadPin = true;
      _requiresPin = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN güncellendi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(profilesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profileId == null ? 'Yeni profil' : 'Profili düzenle'),
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) =>
            Center(child: Text('Hata: $e')),
        data: (List<UserProfile> list) {
          _hydrateIfNeeded(list);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(DesignTokens.spaceL),
              children: <Widget>[
                Center(
                  child: ProfileAvatar(
                    profile: UserProfile(
                      id: 'preview',
                      name: _nameCtrl.text.isEmpty ? 'Profil' : _nameCtrl.text,
                      avatarColor: _avatarColor ?? kProfileAvatarPalette.first,
                      avatarEmoji: _avatarEmoji,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ),
                    size: 96,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceL),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Profil adı',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? v) =>
                      v == null || v.trim().isEmpty ? 'Ad gerekli' : null,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: DesignTokens.spaceL),
                Text(
                  'Avatar',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: DesignTokens.spaceS),
                Wrap(
                  spacing: DesignTokens.spaceS,
                  runSpacing: DesignTokens.spaceS,
                  children: <Widget>[
                    for (final e in _kAvatarEmojis)
                      ChoiceChip(
                        label: Text(
                          e,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        selected: _avatarEmoji == e,
                        onSelected: (_) => setState(() => _avatarEmoji = e),
                      ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceL),
                Text(
                  'Renk',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: DesignTokens.spaceS),
                Wrap(
                  spacing: DesignTokens.spaceS,
                  runSpacing: DesignTokens.spaceS,
                  children: <Widget>[
                    for (final c in kProfileAvatarPalette)
                      InkWell(
                        onTap: () => setState(() => _avatarColor = c),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _avatarColor?.toARGB32() == c.toARGB32()
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Divider(height: DesignTokens.spaceXl),
                SwitchListTile(
                  title: const Text('Çocuk profili'),
                  subtitle: const Text(
                    'İçerikleri yaş kısıtlamasıyla göster',
                  ),
                  value: _isKids,
                  onChanged: (bool v) => setState(() => _isKids = v),
                ),
                SwitchListTile(
                  title: const Text('PIN gerekli'),
                  subtitle: const Text(
                    'Profile geçmek için PIN sor',
                  ),
                  value: _requiresPin,
                  onChanged: (bool v) => setState(() {
                    _requiresPin = v;
                    if (!v) _newPin = null;
                  }),
                ),
                if (_hadPin && widget.profileId != null)
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text("PIN'i değiştir"),
                    onTap: _changePin,
                  ),
                const SizedBox(height: DesignTokens.spaceL),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Kaydet'),
                ),
                if (widget.profileId != null &&
                    widget.profileId != ProfileController.defaultProfileSentinel)
                  Padding(
                    padding:
                        const EdgeInsets.only(top: DesignTokens.spaceM),
                    child: TextButton.icon(
                      onPressed: _saving ? null : () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Profili sil'),
                      style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final controller = ref.read(profileControllerProvider);
    final id = widget.profileId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Profil silinsin mi?'),
        content: const Text(
          'Bu profilin favorileri ve geçmişi kalıcı olarak silinir.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.deleteProfile(id);
      if (!mounted) return;
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    }
  }
}
