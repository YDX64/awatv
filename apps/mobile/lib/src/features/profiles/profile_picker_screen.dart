import 'package:awatv_mobile/src/shared/profiles/profile.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_controller.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "Bu kim?" — Netflix-style profile picker.
///
/// Renders the user's profile list as a 90x90 cherry-tile grid with
/// edit/lock badges. Tapping a profile selects it (or opens the PIN
/// modal first when one is set); long-pressing routes to the edit
/// screen. The header surfaces an "Düzenle" toggle that flips the grid
/// into edit mode where every avatar carries an edit pencil badge.
class ProfilePickerScreen extends ConsumerStatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  ConsumerState<ProfilePickerScreen> createState() =>
      _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends ConsumerState<ProfilePickerScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(profilesListProvider);
    final activeProfile = ref.watch(activeProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        bottom: false,
        child: asyncList.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Profiller yüklenemedi: $e',
                style: const TextStyle(color: Color(0xCCFFFFFF)),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (List<UserProfile> profiles) => _Body(
            profiles: profiles,
            editing: _editing,
            activeId: activeProfile?.id,
            onToggleEdit: () => setState(() => _editing = !_editing),
            onTap: _handleTap,
            onLongPress: (UserProfile p) => context.push('/profiles/edit/${p.id}'),
            onAdd: () => context.push('/profiles/edit'),
            onManage: () => context.push('/settings'),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(UserProfile profile) async {
    if (_editing) {
      await context.push('/profiles/edit/${profile.id}');
      return;
    }
    final controller = ref.read(profileControllerProvider);
    if (profile.requiresPin && profile.hasPin) {
      final ok = await PinNumpadModal.show(
        context: context,
        profile: profile,
        verify: (String pin) => controller.verifyPin(profile, pin),
      );
      if (ok != true) return;
      try {
        // PIN already verified inside the modal — short-circuit the
        // controller's PIN check so we don't double-prompt.
        await controller.switchTo(profile.id, skipPin: true);
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profil değiştirilemedi: $e')),
        );
        return;
      }
      if (!mounted) return;
      context.go('/home');
      return;
    }
    try {
      await controller.switchTo(profile.id, skipPin: true);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profil değiştirilemedi: $e')),
      );
      return;
    }
    if (!mounted) return;
    context.go('/home');
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.profiles,
    required this.editing,
    required this.activeId,
    required this.onToggleEdit,
    required this.onTap,
    required this.onLongPress,
    required this.onAdd,
    required this.onManage,
  });

  final List<UserProfile> profiles;
  final bool editing;
  final String? activeId;
  final VoidCallback onToggleEdit;
  final ValueChanged<UserProfile> onTap;
  final ValueChanged<UserProfile> onLongPress;
  final VoidCallback onAdd;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _TopBar(editing: editing, onToggle: onToggleEdit),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
            child: Column(
              children: <Widget>[
                if (!editing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 32),
                    child: Text(
                      'Bu kim?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    for (final UserProfile p in profiles)
                      ProfilePickerTile(
                        profile: p,
                        editing: editing,
                        active: !editing && p.id == activeId,
                        onTap: () => onTap(p),
                        onLongPress: () => onLongPress(p),
                      ),
                    AddProfileTile(onTap: onAdd),
                  ],
                ),
                const SizedBox(height: 32),
                Center(
                  child: TextButton(
                    onPressed: onManage,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xCCFFFFFF),
                    ),
                    child: const Text(
                      'Profilleri yönet',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.editing, required this.onToggle});

  final bool editing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          if (editing)
            const Text(
              'Profilleri Düzenle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            )
          else
            const SizedBox(width: 80),
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: editing ? Colors.white : Colors.transparent,
                border: Border.all(
                  color: editing ? Colors.white : const Color(0x66FFFFFF),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                editing ? 'Tamam' : 'Profili Düzenle',
                style: TextStyle(
                  color: editing ? const Color(0xFF0A0A0A) : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single tile in the profile picker grid — 90×90 rounded square,
/// avatar emoji centered, optional lock/edit badge in the bottom-right
/// corner. The active profile in idle mode picks up a 3px white
/// border per the Streas spec.
class ProfilePickerTile extends StatelessWidget {
  const ProfilePickerTile({
    required this.profile,
    required this.editing,
    required this.active,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final UserProfile profile;
  final bool editing;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 100,
        child: Column(
          children: <Widget>[
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: profile.avatarColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active ? Colors.white : Colors.transparent,
                        width: active ? 3 : 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.avatarEmoji ?? '🎭',
                      style: const TextStyle(fontSize: 44, height: 1),
                    ),
                  ),
                  if (editing)
                    const Positioned(
                      bottom: -4,
                      right: -4,
                      child: _CornerBadge(
                        color: BrandColors.primary,
                        icon: Icons.edit_outlined,
                      ),
                    )
                  else if (profile.requiresPin && profile.hasPin)
                    const Positioned(
                      bottom: -4,
                      right: -4,
                      child: _CornerBadge(
                        color: Color(0xCC000000),
                        icon: Icons.lock_outline_rounded,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
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
                    color: BrandColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ÇOCUK',
                    style: TextStyle(
                      color: BrandColors.primary,
                      fontSize: 10,
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

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 10, color: Colors.white),
    );
  }
}

class AddProfileTile extends StatelessWidget {
  const AddProfileTile({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 100,
        child: Column(
          children: <Widget>[
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                border: Border.all(color: const Color(0x33FFFFFF)),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.add_rounded,
                size: 32,
                color: Color(0x99FFFFFF),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Profil Ekle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x80FFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen-ish PIN modal triggered when the user taps a PIN-locked
/// profile. Returns `true` on a verified entry, `false`/`null` on
/// cancel.
class PinNumpadModal extends StatefulWidget {
  const PinNumpadModal({
    required this.profile,
    required this.verify,
    super.key,
  });

  final UserProfile profile;
  final bool Function(String pin) verify;

  static Future<bool?> show({
    required BuildContext context,
    required UserProfile profile,
    required bool Function(String pin) verify,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: const Color(0xCC000000),
      barrierDismissible: true,
      builder: (BuildContext _) => Center(
        child: PinNumpadModal(profile: profile, verify: verify),
      ),
    );
  }

  @override
  State<PinNumpadModal> createState() => _PinNumpadModalState();
}

class _PinNumpadModalState extends State<PinNumpadModal> {
  String _pin = '';
  bool _error = false;
  bool _checking = false;

  void _onKey(String key) {
    if (_checking) return;
    if (key == '⌫') {
      setState(() {
        _pin = _pin.isEmpty ? _pin : _pin.substring(0, _pin.length - 1);
        _error = false;
      });
      return;
    }
    if (_pin.length >= 4) return;
    final next = _pin + key;
    setState(() {
      _pin = next;
      _error = false;
    });
    HapticFeedback.lightImpact();
    if (next.length == 4) {
      _checking = true;
      Future<void>.delayed(const Duration(milliseconds: 200), _verify);
    }
  }

  void _verify() {
    if (!mounted) return;
    final ok = widget.verify(_pin);
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } else {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = true;
        _pin = '';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Profil PIN gir',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: widget.profile.avatarColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.profile.avatarEmoji ?? '🎭',
                  style: const TextStyle(fontSize: 36, height: 1),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.profile.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              PinDots(filled: _pin.length, variant: PinDotsVariant.modal),
              if (_error) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  'PIN yanlış. Tekrar dene.',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ] else
                const SizedBox(height: 12),
              PinNumpad(
                onKey: _onKey,
                size: PinNumpadSize.large,
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Vazgeç',
                    style: TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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

enum PinDotsVariant { modal, form }

/// Streas PIN dots — 4 14×14 circles with 14px spacing. The "modal"
/// variant uses solid white fills, the "form" variant uses cherry
/// fills with a 1px hairline border (used inside the profile editor).
class PinDots extends StatelessWidget {
  const PinDots({
    required this.filled,
    required this.variant,
    super.key,
  });

  final int filled;
  final PinDotsVariant variant;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(4, (int i) {
        final isFilled = i < filled;
        return Padding(
          padding: EdgeInsets.only(right: i == 3 ? 0 : 14),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled
                  ? (variant == PinDotsVariant.modal
                      ? Colors.white
                      : BrandColors.primary)
                  : (variant == PinDotsVariant.modal
                      ? const Color(0x33FFFFFF)
                      : Colors.transparent),
              border: variant == PinDotsVariant.form
                  ? Border.all(color: const Color(0x4DFFFFFF))
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

enum PinNumpadSize { large, small }

/// 12-cell numpad: 1-9 / "" 0 ⌫. The empty cell stays in the layout
/// so the bottom row maintains its 3-column grid.
class PinNumpad extends StatelessWidget {
  const PinNumpad({
    required this.onKey,
    required this.size,
    super.key,
  });

  final ValueChanged<String> onKey;
  final PinNumpadSize size;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == PinNumpadSize.large;
    final keyWidth = isLarge ? 64.0 : 58.0;
    final keyHeight = isLarge ? 54.0 : 48.0;
    final radius = isLarge ? 10.0 : 8.0;
    final fontSize = isLarge ? 22.0 : 20.0;
    final width = isLarge ? 220.0 : 200.0;

    const labels = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final label in labels)
            SizedBox(
              width: keyWidth,
              height: keyHeight,
              child: Opacity(
                opacity: label.isEmpty ? 0 : 1,
                child: Material(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(radius),
                  child: InkWell(
                    onTap: label.isEmpty ? null : () => onKey(label),
                    borderRadius: BorderRadius.circular(radius),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w400,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
