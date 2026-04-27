import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../shared/service_providers.dart';
import 'playlist_providers.dart';

/// Form for adding a new playlist.
///
/// Two segments:
///   - **M3U / M3U8**: just a URL.
///   - **Xtream Codes**: server URL + username + password.
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

  PlaylistKind _kind = PlaylistKind.m3u;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _epgCtrl.dispose();
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

  String? _validateXtreamCreds(String? v) {
    if (v == null || v.trim().isEmpty) return 'Bu alan zorunlu';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);

    try {
      final source = PlaylistSource(
        id: const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        kind: _kind,
        url: _urlCtrl.text.trim(),
        addedAt: DateTime.now(),
        username: _kind == PlaylistKind.xtream ? _userCtrl.text.trim() : null,
        password: _kind == PlaylistKind.xtream ? _passCtrl.text : null,
        epgUrl: _epgCtrl.text.trim().isEmpty ? null : _epgCtrl.text.trim(),
      );

      await ref.read(playlistServiceProvider).add(source);
      ref.invalidate(playlistsProvider);
      ref.invalidate(allChannelsProvider);

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
                  ] else ...[
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
