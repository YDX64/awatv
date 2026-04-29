import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/shared/discovery/discovered_iptv_server.dart';
import 'package:awatv_mobile/src/shared/discovery/local_iptv_discovery.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

/// Form for adding a new playlist.
///
/// Three segments:
///   - **M3U / M3U8**: just a URL.
///   - **Xtream Codes**: server URL + username + password.
///   - **Stalker Portal**: portal URL + MAC address (+ optional time-zone).
///
/// Submission goes through `PlaylistService.add(...)`, which both persists
/// the source AND triggers an initial sync. Errors bubble up as a SnackBar.
class AddPlaylistScreen extends ConsumerStatefulWidget {
  const AddPlaylistScreen({super.key});

  @override
  ConsumerState<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends ConsumerState<AddPlaylistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _epgCtrl = TextEditingController();
  final _macCtrl = TextEditingController();

  PlaylistKind _kind = PlaylistKind.m3u;
  bool _busy = false;
  bool _showPassword = false;
  String _stalkerTimezone = 'Europe/Istanbul';

  /// Common IANA time-zones surfaced as a dropdown for the Stalker form.
  /// Rolling our own short list rather than pulling in `flutter_timezone`
  /// keeps the bundle small; the user can still pick "Diger / UTC" if
  /// their region isn't one of these.
  static const List<String> _timezones = <String>[
    'Europe/Istanbul',
    'Europe/Berlin',
    'Europe/London',
    'Europe/Paris',
    'Europe/Moscow',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Tehran',
    'Asia/Dubai',
    'UTC',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _epgCtrl.dispose();
    _macCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Bir isim ver';
    return null;
  }

  String? _validateUrl(String? v) {
    if (v == null || v.trim().isEmpty) return 'URL gerekli';
    final uri = Uri.tryParse(v.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'http(s) ile basla';
    }
    return null;
  }

  String? _validateXtreamServer(String? v) {
    final base = _validateUrl(v);
    if (base != null) return base;
    if (v!.contains('player_api.php')) {
      return 'Sadece sunucu adresini gir, /player_api.php olmadan';
    }
    return null;
  }

  String? _validateStalkerServer(String? v) {
    final base = _validateUrl(v);
    if (base != null) return base;
    return null;
  }

  String? _validateXtreamCreds(String? v) {
    if (v == null || v.trim().isEmpty) return 'Bu alan zorunlu';
    return null;
  }

  String? _validateMac(String? v) {
    if (v == null || v.trim().isEmpty) return 'MAC adresi gerekli';
    if (!StalkerClient.isValidMac(v.trim())) {
      return 'Format: 00:1A:79:XX:XX:XX';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);

    try {
      // For the Stalker kind we reuse `username` for the MAC (canonicalised)
      // and `password` for the timezone hint — see PlaylistKind.stalker doc.
      String? username;
      String? password;
      switch (_kind) {
        case PlaylistKind.m3u:
          username = null;
          password = null;
        case PlaylistKind.xtream:
          username = _userCtrl.text.trim();
          password = _passCtrl.text;
        case PlaylistKind.stalker:
          username = StalkerClient.normaliseMac(_macCtrl.text.trim());
          password = _stalkerTimezone;
      }

      final source = PlaylistSource(
        id: const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        kind: _kind,
        url: _urlCtrl.text.trim(),
        addedAt: DateTime.now(),
        username: username,
        password: password,
        epgUrl: _epgCtrl.text.trim().isEmpty ? null : _epgCtrl.text.trim(),
      );

      await ref.read(playlistServiceProvider).add(source);
      ref
        ..invalidate(playlistsProvider)
        ..invalidate(allChannelsProvider);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('"${source.name}" eklendi')),
      );
      navigator.go('/live');
    } on XtreamAuthException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Kimlik dogrulanamadi: ${e.message}')),
      );
    } on StalkerAuthException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Stalker portal hatasi: ${e.message}')),
      );
    } on PlaylistParseException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Liste cozumlenemedi: ${e.message}')),
      );
    } on NetworkException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ag hatasi: ${e.message}')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Eklenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Bul" button on the Stalker tab — probes the URL by visiting
  /// `/portal.php?type=stb&action=ping` and surfaces the result.
  Future<void> _probeStalker() async {
    final url = _urlCtrl.text.trim();
    final mac = _macCtrl.text.trim();
    if (_validateStalkerServer(url) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Once gecerli bir portal URL gir')),
      );
      return;
    }
    if (_validateMac(mac) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Once gecerli bir MAC adresi gir')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final client = StalkerClient(
        portalUrl: url,
        macAddress: mac,
        timezone: _stalkerTimezone,
        dio: ref.read(dioProvider),
      );
      await client.handshake();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Portal bulundu, MAC yetkili.')),
      );
    } on StalkerAuthException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Portal reddetti: ${e.message}')),
      );
    } on NetworkException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Portala ulasilamadi: ${e.message}')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Probe basarisiz: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Liste ekle')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<PlaylistKind>(
                    segments: const <ButtonSegment<PlaylistKind>>[
                      ButtonSegment<PlaylistKind>(
                        value: PlaylistKind.m3u,
                        label: Text('M3U / M3U8'),
                        icon: Icon(Icons.list_alt_rounded),
                      ),
                      ButtonSegment<PlaylistKind>(
                        value: PlaylistKind.xtream,
                        label: Text('Xtream Codes'),
                        icon: Icon(Icons.vpn_key_outlined),
                      ),
                      ButtonSegment<PlaylistKind>(
                        value: PlaylistKind.stalker,
                        label: Text('Stalker Portal'),
                        icon: Icon(Icons.dns_outlined),
                      ),
                    ],
                    selected: <PlaylistKind>{_kind},
                    onSelectionChanged: (Set<PlaylistKind> set) {
                      setState(() => _kind = set.first);
                    },
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  TextFormField(
                    controller: _nameCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Isim',
                      hintText: 'Ornek: Evdeki IPTV',
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  if (_kind == PlaylistKind.m3u) ...[
                    TextFormField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'M3U URL',
                        hintText: 'https://example.com/playlist.m3u',
                      ),
                      validator: _validateUrl,
                    ),
                  ] else if (_kind == PlaylistKind.xtream) ...[
                    TextFormField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Sunucu URL',
                        hintText: 'http://my.iptv.host:8080',
                      ),
                      validator: _validateXtreamServer,
                    ),
                    const SizedBox(height: DesignTokens.spaceS),
                    _LocalDiscoveryPanel(
                      onPick: (DiscoveredIptvServer s) {
                        _urlCtrl.text = s.suggestedUrl;
                        if (_nameCtrl.text.trim().isEmpty) {
                          _nameCtrl.text = s.name;
                        }
                        FocusScope.of(context).nextFocus();
                      },
                    ),
                    const SizedBox(height: DesignTokens.spaceM),
                    TextFormField(
                      controller: _userCtrl,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Kullanici adi',
                      ),
                      validator: _validateXtreamCreds,
                    ),
                    const SizedBox(height: DesignTokens.spaceM),
                    TextFormField(
                      controller: _passCtrl,
                      autocorrect: false,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Sifre',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: _validateXtreamCreds,
                    ),
                  ] else ...[
                    // Stalker Portal
                    TextFormField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Portal URL',
                        hintText: 'http://portal.example.tv:8080',
                        helperText:
                            '/portal.php yolunu eklemen gerekmez, otomatik tespit edilir',
                      ),
                      validator: _validateStalkerServer,
                    ),
                    const SizedBox(height: DesignTokens.spaceM),
                    TextFormField(
                      controller: _macCtrl,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      inputFormatters: <TextInputFormatter>[
                        _MacAddressFormatter(),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'MAC adresi',
                        hintText: '00:1A:79:XX:XX:XX',
                      ),
                      validator: _validateMac,
                    ),
                    const SizedBox(height: DesignTokens.spaceM),
                    DropdownButtonFormField<String>(
                      initialValue: _stalkerTimezone,
                      decoration: const InputDecoration(
                        labelText: 'Saat dilimi (opsiyonel)',
                      ),
                      items: <DropdownMenuItem<String>>[
                        for (final tz in _timezones)
                          DropdownMenuItem<String>(
                            value: tz,
                            child: Text(tz),
                          ),
                      ],
                      onChanged: (String? v) {
                        if (v == null) return;
                        setState(() => _stalkerTimezone = v);
                      },
                    ),
                    const SizedBox(height: DesignTokens.spaceM),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _probeStalker,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Bul'),
                    ),
                    const SizedBox(height: DesignTokens.spaceS),
                    Text(
                      'Portal MAC adresimizi tanimak zorunda. Saglayicidan '
                      'cihazi yetkilendirmesini iste.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignTokens.spaceL),
                  ExpansionTile(
                    title: const Text('Gelismis'),
                    childrenPadding: const EdgeInsets.symmetric(
                      vertical: DesignTokens.spaceS,
                    ),
                    children: [
                      TextFormField(
                        controller: _epgCtrl,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'EPG URL (opsiyonel)',
                          hintText: 'https://example.com/epg.xml.gz',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ekle ve senkron et'),
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  Text(
                    'Liste ilk eklenisinde indirilir ve cihazda saklanir. '
                    'Daha sonra cevrimdisi gezilebilir.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Auto-formats input as a colon-separated MAC. Drops anything that
/// isn't a hex digit, then re-inserts colons every 2 chars (cap 12).
class _MacAddressFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final hex = newValue.text
        .toUpperCase()
        .replaceAll(RegExp('[^0-9A-F]'), '');
    final capped = hex.length > 12 ? hex.substring(0, 12) : hex;
    final buf = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i > 0 && i.isEven) buf.write(':');
      buf.write(capped[i]);
    }
    final out = buf.toString();
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// Expandable section that lists IPTV-ish services advertising via mDNS
/// on the local network. Tapping a row pushes the suggested URL into the
/// parent form's Server URL field (via the supplied [onPick]).
///
/// Hidden entirely on web — Bonsoir doesn't ship a browser implementation.
class _LocalDiscoveryPanel extends ConsumerWidget {
  const _LocalDiscoveryPanel({required this.onPick});

  final ValueChanged<DiscoveredIptvServer> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final discovery = ref.watch(localIptvDiscoveryProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.wifi_find_outlined),
        title: const Text('Yerel agda bulunan sunucular'),
        subtitle: discovery.when(
          data: (List<DiscoveredIptvServer> values) {
            if (values.isEmpty) {
              return const Text('Henuz sunucu bulunamadi - tarama suruyor.');
            }
            return Text(
              '${values.length} sunucu bulundu - tap ile sec',
            );
          },
          loading: () => const Text('Aglarda taranıyor...'),
          error: (Object _, StackTrace __) =>
              const Text('Tarama yapilamadi'),
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceS,
          vertical: DesignTokens.spaceXs,
        ),
        children: <Widget>[
          discovery.when(
            data: (List<DiscoveredIptvServer> values) {
              if (values.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(DesignTokens.spaceM),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.lan_outlined, size: 18),
                      const SizedBox(width: DesignTokens.spaceS),
                      Expanded(
                        child: Text(
                          'Sunucularin Bonjour servisi yayinlamasi gerekir. '
                          'Manuel olarak da girebilirsin.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (final s in values)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        s.type.contains('xtream')
                            ? Icons.satellite_alt_outlined
                            : Icons.router_outlined,
                        size: 22,
                      ),
                      title: Text(s.name),
                      subtitle: Text(
                        '${s.host}:${s.port} - ${s.type}',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.add_link_rounded, size: 20),
                      onTap: () => onPick(s),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(DesignTokens.spaceM),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (Object err, StackTrace _) => Padding(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              child: Text(
                'Yerel ag taramasi yapilamadi: $err',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
