import 'package:awatv_mobile/src/features/profiles/profile_avatar_pool.dart';
import 'package:awatv_mobile/src/features/profiles/profile_picker_screen.dart'
    show PinDots, PinDotsVariant, PinNumpad, PinNumpadSize;
import 'package:awatv_mobile/src/shared/profiles/profile.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Streas-style profile editor.
///
/// Layout (top → bottom):
///   * Cancel / title / Save (or Done) header.
///   * Optional "primary profile" note for the default profile.
///   * 90×90 big avatar + cherry edit badge → tap to expand picker.
///   * Avatar emoji grid (6 per row) + colour swatches (12 chips).
///   * Profile name input.
///   * "PLAYBACK AND LANGUAGE SETTINGS" card with Junior Mode + PIN
///     toggles, and a 4-digit PIN entry block when PIN is enabled.
///   * Delete / two-step confirm box (non-primary only).
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({this.profileId, super.key});

  final String? profileId;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _hydrated = false;
  bool _saving = false;
  bool _pickerOpen = false;
  bool _juniorMode = false;
  bool _pinEnabled = false;
  bool _hadPin = false;
  bool _confirmDelete = false;
  String? _nameError;
  String _pin = '';
  int _avatarIndex = 0;
  int _colorIndex = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.profileId != null;

  bool get _isPrimary =>
      _isEditing &&
      widget.profileId == ProfileController.defaultProfileSentinel;

  void _hydrate(List<UserProfile> list) {
    if (_hydrated) return;
    UserProfile? profile;
    final id = widget.profileId;
    if (id != null) {
      for (final p in list) {
        if (p.id == id) {
          profile = p;
          break;
        }
      }
    }
    if (profile != null) {
      _nameController.text = profile.name;
      _avatarIndex = avatarEmojiIndexFor(profile.avatarEmoji);
      _colorIndex = avatarColorIndexFor(profile.avatarColor);
      _juniorMode = profile.isKids;
      _pinEnabled = profile.requiresPin && profile.hasPin;
      _hadPin = profile.hasPin;
    }
    _hydrated = true;
  }

  String get _emoji => kStreasAvatarEmojis[_avatarIndex];
  Color get _color => kStreasAvatarColors[_colorIndex];

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Profil adı gerekli');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    try {
      final controller = ref.read(profileControllerProvider);
      final pinToSet = _pinEnabled && _pin.length == 4 ? _pin : null;
      if (_isEditing) {
        await controller.updateProfile(
          widget.profileId!,
          name: name,
          avatarEmoji: _emoji,
          avatarColor: _color,
          isKids: _juniorMode,
          requiresPin: _pinEnabled,
          pin: pinToSet,
          clearPin: !_pinEnabled,
        );
      } else {
        await controller.createProfile(
          name: name,
          avatarEmoji: _emoji,
          avatarColor: _color,
          isKids: _juniorMode,
          requiresPin: _pinEnabled,
          pin: pinToSet,
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

  Future<void> _delete() async {
    final id = widget.profileId;
    if (id == null || _isPrimary) return;
    try {
      await ref.read(profileControllerProvider).deleteProfile(id);
      if (!mounted) return;
      context.go('/profiles');
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    }
  }

  void _onPinKey(String key) {
    if (key == '⌫') {
      setState(() {
        _pin = _pin.isEmpty ? _pin : _pin.substring(0, _pin.length - 1);
      });
      return;
    }
    if (_pin.length >= 4) return;
    setState(() => _pin = _pin + key);
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(profilesListProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        bottom: false,
        child: asyncList.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace _) =>
              Center(child: Text('Hata: $e', style: const TextStyle(color: Colors.white))),
          data: (List<UserProfile> list) {
            _hydrate(list);
            return _Form(
              isEditing: _isEditing,
              isPrimary: _isPrimary,
              saving: _saving,
              onCancel: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/profiles');
                }
              },
              onSave: _save,
              children: <Widget>[
                if (_isPrimary) const _PrimaryNote(),
                _BigAvatar(
                  emoji: _emoji,
                  color: _color,
                  onTap: () => setState(() => _pickerOpen = !_pickerOpen),
                ),
                if (_pickerOpen)
                  _AvatarPicker(
                    avatarIndex: _avatarIndex,
                    colorIndex: _colorIndex,
                    onAvatarSelected: (int i) =>
                        setState(() => _avatarIndex = i),
                    onColorSelected: (int i) =>
                        setState(() => _colorIndex = i),
                  ),
                _NameField(
                  controller: _nameController,
                  error: _nameError,
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
                const _SectionLabel('OYNATMA VE DİL AYARLARI'),
                _SettingsCard(
                  children: <Widget>[
                    if (!_isPrimary)
                      _SettingRow(
                        title: 'Çocuk Modu',
                        description:
                            'Yaş kısıtlamasıyla küratörlü içerik ve sadeleştirilmiş arayüz.',
                        value: _juniorMode,
                        onChanged: (bool v) =>
                            setState(() => _juniorMode = v),
                      ),
                    _SettingRow(
                      title: 'Profil PIN',
                      description: 'Bu profile geçişi 4 haneli PIN ile kısıtla.',
                      value: _pinEnabled,
                      onChanged: (bool v) => setState(() {
                        _pinEnabled = v;
                        if (!v) _pin = '';
                      }),
                      isLast: !_pinEnabled,
                    ),
                    if (_pinEnabled)
                      _PinEntryBlock(
                        pin: _pin,
                        onKey: _onPinKey,
                        showHint: !_hadPin,
                      ),
                  ],
                ),
                if (_isEditing && !_isPrimary)
                  _DeleteAction(
                    confirm: _confirmDelete,
                    onAskConfirm: () =>
                        setState(() => _confirmDelete = true),
                    onCancel: () =>
                        setState(() => _confirmDelete = false),
                    onDelete: _delete,
                  ),
                const SizedBox(height: 60),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.isEditing,
    required this.isPrimary,
    required this.saving,
    required this.onCancel,
    required this.onSave,
    required this.children,
  });

  final bool isEditing;
  final bool isPrimary;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _Header(
          isEditing: isEditing,
          saving: saving,
          onCancel: onCancel,
          onSave: onSave,
        ),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isEditing,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool isEditing;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: onCancel,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Vazgeç',
                style: TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                isEditing ? 'Profili Düzenle' : 'Profil Ekle',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: saving ? null : onSave,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      isEditing ? 'Tamam' : 'Kaydet',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryNote extends StatelessWidget {
  const _PrimaryNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Bu senin ana profilin. Silinemez ve Çocuk Modu açılamaz.',
        style: TextStyle(
          color: Color(0x8CFFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 18 / 12,
        ),
      ),
    );
  }
}

class _BigAvatar extends StatelessWidget {
  const _BigAvatar({
    required this.emoji,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 130,
            height: 100,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 50, height: 1),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 8,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: BrandColors.primary,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFF0A0A0A)),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.avatarIndex,
    required this.colorIndex,
    required this.onAvatarSelected,
    required this.onColorSelected,
  });

  final int avatarIndex;
  final int colorIndex;
  final ValueChanged<int> onAvatarSelected;
  final ValueChanged<int> onColorSelected;

  @override
  Widget build(BuildContext context) {
    final selectedColor = kStreasAvatarColors[colorIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SectionLabel('AVATAR SEÇ', tightLeft: true),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (var i = 0; i < kStreasAvatarEmojis.length; i++)
                GestureDetector(
                  onTap: () => onAvatarSelected(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: avatarIndex == i
                          ? selectedColor
                          : const Color(0x14FFFFFF),
                      border: Border.all(
                        color: avatarIndex == i
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      kStreasAvatarEmojis[i],
                      style: const TextStyle(fontSize: 28, height: 1),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _SectionLabel('RENK SEÇ', tightLeft: true),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (var i = 0; i < kStreasAvatarColors.length; i++)
                GestureDetector(
                  onTap: () => onColorSelected(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kStreasAvatarColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorIndex == i
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String? error;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              border: Border.all(
                color: error != null
                    ? const Color(0xFFEF4444)
                    : const Color(0x26FFFFFF),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: controller,
              maxLength: 20,
              onChanged: onChanged,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
                border: InputBorder.none,
                counterText: '',
                hintText: 'Profil Adı',
                hintStyle: TextStyle(
                  color: Color(0x59FFFFFF),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.tightLeft = false});

  final String label;
  final bool tightLeft;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(tightLeft ? 0 : 20, 16, 20, 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0x73FFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xCC0F1A2E),
        border: Border.all(color: const Color(0x14FFFFFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0x12FFFFFF)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0x73FFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    height: 16 / 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: BrandColors.primary,
            inactiveTrackColor: const Color(0x26FFFFFF),
            inactiveThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _PinEntryBlock extends StatelessWidget {
  const _PinEntryBlock({
    required this.pin,
    required this.onKey,
    required this.showHint,
  });

  final String pin;
  final ValueChanged<String> onKey;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          if (showHint)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Bu profile geçişi 4 haneli bir PIN ile kısıtla.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0x80FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          PinDots(filled: pin.length, variant: PinDotsVariant.form),
          const SizedBox(height: 12),
          PinNumpad(onKey: onKey, size: PinNumpadSize.small),
        ],
      ),
    );
  }
}

class _DeleteAction extends StatelessWidget {
  const _DeleteAction({
    required this.confirm,
    required this.onAskConfirm,
    required this.onCancel,
    required this.onDelete,
  });

  final bool confirm;
  final VoidCallback onAskConfirm;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (!confirm) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: GestureDetector(
          onTap: onAskConfirm,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Profili Sil',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xE60F1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          const Text(
            'Bu profil silinsin mi?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tüm izleme geçmişi ve ayarlar kaybolacak.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: GestureDetector(
                  onTap: onCancel,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x33FFFFFF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Vazgeç',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Sil',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
