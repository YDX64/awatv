import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/shared/discovery/discovered_iptv_server.dart';
import 'package:awatv_mobile/src/shared/discovery/local_iptv_discovery.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Visual tab on the Add Playlist screen.
///
/// Mirrors the 3 type cards in `app/add-source.tsx` of the Streas RN
/// reference. The Stalker variant lives behind a small "advanced" link
/// for users on regional ISPs that ship Ministra portals — keeping it
/// off the main row stops casual users from accidentally picking it.
enum _SourceTab { xtream, m3u, file, stalker }

/// Add-playlist form rebuilt to match the Streas RN reference.
///
/// Top-down anatomy:
///   1. Header bar with close, title, save button on the right.
///   2. 3-card type selector: Xtream / M3U / Local File. Stalker is
///      reachable via the "advanced" link below the cards.
///   3. Type-specific form (info note → fields).
///   4. Sample-playlist rail (M3U tab only).
///   5. Optional name field with type-aware hint.
///   6. Test Connection button (Xtream + M3U).
///   7. Verified / error banner.
///   8. Bottom info card with bullet list keyed off type.
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

  _SourceTab _tab = _SourceTab.xtream;
  bool _busy = false;
  bool _showPassword = false;
  bool _testing = false;
  String? _verifiedMessage;
  String? _errorMessage;
  String? _selectedSampleId;
  String _stalkerTimezone = 'Europe/Istanbul';

  // Local file pick state.
  XFile? _pickedFile;
  String? _pickedFileFormat; // upper-case (e.g. M3U8)
  int? _pickedFileSizeBytes;
  int? _pickedFileChannelCount;
  String? _pickedFileContent;
  bool _pickingFile = false;

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

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validateUrl(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'playlists.validation_url_required'.tr();
    }
    final uri = Uri.tryParse(v.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'playlists.form_validation_url_scheme'.tr();
    }
    return null;
  }

  String? _validateXtreamServer(String? v) {
    final base = _validateUrl(v);
    if (base != null) return base;
    if (v!.contains('player_api.php')) {
      return 'playlists.form_validation_xtream_no_player_api'.tr();
    }
    return null;
  }

  String? _validateXtreamCreds(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'playlists.form_validation_field_required'.tr();
    }
    return null;
  }

  String? _validateMac(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'playlists.form_validation_mac_required'.tr();
    }
    if (!StalkerClient.isValidMac(v.trim())) {
      return 'playlists.form_validation_mac_format'.tr();
    }
    return null;
  }

  /// True iff the current form state is enough to attempt save.
  ///
  /// Mirrors Streas's `canSave` boolean: at least the type-mandatory
  /// fields are populated (name is optional and auto-derives if blank).
  bool get _canSave {
    if (_busy) return false;
    switch (_tab) {
      case _SourceTab.xtream:
        return _urlCtrl.text.trim().isNotEmpty &&
            _userCtrl.text.trim().isNotEmpty &&
            _passCtrl.text.isNotEmpty;
      case _SourceTab.m3u:
        return _urlCtrl.text.trim().isNotEmpty;
      case _SourceTab.file:
        return _pickedFile != null && _pickedFileChannelCount != null;
      case _SourceTab.stalker:
        return _urlCtrl.text.trim().isNotEmpty &&
            _macCtrl.text.trim().isNotEmpty;
    }
  }

  // ---------------------------------------------------------------------------
  // Tab + form state
  // ---------------------------------------------------------------------------

  void _switchTab(_SourceTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _verifiedMessage = null;
      _errorMessage = null;
      _selectedSampleId = null;
      _pickedFile = null;
      _pickedFileFormat = null;
      _pickedFileSizeBytes = null;
      _pickedFileChannelCount = null;
      _pickedFileContent = null;
    });
  }

  void _onSamplePlaylistTap(SamplePlaylistPreset preset) {
    setState(() {
      _selectedSampleId = preset.id;
      _urlCtrl.text = preset.url;
      _verifiedMessage = null;
      _errorMessage = null;
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = preset.name;
      }
    });
  }

  String _hintForName() {
    switch (_tab) {
      case _SourceTab.xtream:
        return 'My IPTV';
      case _SourceTab.m3u:
        return 'Sports Package';
      case _SourceTab.file:
        if (_pickedFile != null) {
          final base = _pickedFile!.name;
          final dot = base.lastIndexOf('.');
          return dot > 0 ? base.substring(0, dot) : base;
        }
        return 'playlists.form_name_hint'.tr();
      case _SourceTab.stalker:
        return 'Stalker portal';
    }
  }

  String _autoNameFallback() {
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty) return name;
    switch (_tab) {
      case _SourceTab.xtream:
        final user = _userCtrl.text.trim();
        final host = Uri.tryParse(_urlCtrl.text.trim())?.host ?? '';
        if (user.isNotEmpty && host.isNotEmpty) return '$user @ $host';
        return user.isNotEmpty ? user : 'Xtream IPTV';
      case _SourceTab.m3u:
        final host = Uri.tryParse(_urlCtrl.text.trim())?.host;
        return (host != null && host.isNotEmpty) ? host : 'M3U Playlist';
      case _SourceTab.file:
        return _pickedFile?.name ?? 'Local Playlist';
      case _SourceTab.stalker:
        final host = Uri.tryParse(_urlCtrl.text.trim())?.host ?? '';
        return host.isNotEmpty ? 'Stalker · $host' : 'Stalker portal';
    }
  }

  // ---------------------------------------------------------------------------
  // File picking
  // ---------------------------------------------------------------------------

  Future<void> _pickLocalFile() async {
    if (_pickingFile) return;
    setState(() {
      _pickingFile = true;
      _errorMessage = null;
      _verifiedMessage = null;
    });
    try {
      const group = XTypeGroup(
        label: 'Playlist',
        extensions: <String>['m3u', 'm3u8', 'txt'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
      if (file == null) {
        setState(() => _pickingFile = false);
        return;
      }
      final body = await file.readAsString();
      // Use a synthetic source-id for the parser — we'll regenerate on save.
      final channels = M3uParser.parse(body, 'preview');
      if (channels.isEmpty) {
        setState(() {
          _pickingFile = false;
          _errorMessage = 'playlists.form_local_file_no_channels'.tr();
        });
        return;
      }

      final size = await file.length();
      final ext = _extensionOf(file.name).toUpperCase();

      setState(() {
        _pickedFile = file;
        _pickedFileSizeBytes = size;
        _pickedFileFormat = ext.isEmpty ? 'M3U' : ext;
        _pickedFileChannelCount = channels.length;
        _pickedFileContent = body;
        _pickingFile = false;
        if (_nameCtrl.text.trim().isEmpty) {
          final base = file.name;
          final dot = base.lastIndexOf('.');
          _nameCtrl.text = dot > 0 ? base.substring(0, dot) : base;
        }
      });
    } on Object catch (e) {
      setState(() {
        _pickingFile = false;
        _errorMessage = 'playlists.form_local_file_pick_failed'.tr(
          namedArgs: <String, String>{'message': e.toString()},
        );
      });
    }
  }

  void _clearPickedFile() {
    setState(() {
      _pickedFile = null;
      _pickedFileFormat = null;
      _pickedFileSizeBytes = null;
      _pickedFileChannelCount = null;
      _pickedFileContent = null;
    });
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ---------------------------------------------------------------------------
  // Test connection
  // ---------------------------------------------------------------------------

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _verifiedMessage = null;
      _errorMessage = null;
    });

    try {
      switch (_tab) {
        case _SourceTab.xtream:
          await _testXtream();
        case _SourceTab.m3u:
          await _testM3u();
        case _SourceTab.file:
        case _SourceTab.stalker:
          // No test-connection affordance for these tabs — the buttons
          // aren't rendered anyway, but bail out defensively.
          break;
      }
    } on Object catch (e) {
      setState(() {
        _errorMessage = 'playlists.form_test_connection_failed'.tr(
          namedArgs: <String, String>{'message': _humanError(e)},
        );
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _testXtream() async {
    final server = _urlCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (_validateXtreamServer(server) != null) {
      setState(() {
        _errorMessage = 'playlists.form_test_connection_url_first'.tr();
      });
      return;
    }
    if (user.isEmpty || pass.isEmpty) {
      setState(() {
        _errorMessage =
            'playlists.form_test_connection_credentials_first'.tr();
      });
      return;
    }

    final dio = ref.read(dioProvider);
    // Light-weight authenticate via the panel; the existing XtreamClient
    // handles every quirk we care about (auth=0, banned, redirected
    // hosts) and throws typed exceptions we can present.
    final client = XtreamClient(
      server: server,
      username: user,
      password: pass,
      dio: dio,
    );
    await client.authenticate();

    // Pull a minimal user_info so we can show a helpful confirmation
    // with the username + max-connections counter. We hit the same
    // endpoint the client uses internally — duplicate request but
    // sub-millisecond on the wire and avoids exposing _api() publicly.
    final response = await dio.getUri<dynamic>(
      Uri.parse('$server/player_api.php').replace(
        queryParameters: <String, String>{
          'username': user,
          'password': pass,
        },
      ),
    );
    final data = response.data;
    int? maxConn;
    String? expiry;
    if (data is Map) {
      final ui = data['user_info'];
      if (ui is Map) {
        final raw = ui['max_connections'];
        if (raw is num) {
          maxConn = raw.toInt();
        } else if (raw is String) {
          maxConn = int.tryParse(raw);
        }
        final exp = ui['exp_date'];
        if (exp is String && exp.isNotEmpty && exp != '0') {
          final epoch = int.tryParse(exp);
          if (epoch != null) {
            final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
            expiry = '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
          }
        }
      }
    }

    final summary = 'playlists.form_test_connection_xtream_summary'.tr(
      namedArgs: <String, String>{
        'username': user,
        'connections': maxConn?.toString() ?? '-',
      },
    );
    final expiryLine = expiry != null
        ? 'playlists.form_test_connection_xtream_expiry'.tr(
            namedArgs: <String, String>{'date': expiry},
          )
        : 'playlists.form_test_connection_xtream_expiry_never'.tr();

    setState(() {
      _verifiedMessage = '$summary\n$expiryLine';
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = _autoNameFallback();
      }
    });
  }

  Future<void> _testM3u() async {
    final url = _urlCtrl.text.trim();
    if (_validateUrl(url) != null) {
      setState(() {
        _errorMessage = 'playlists.form_test_connection_url_first'.tr();
      });
      return;
    }

    final dio = ref.read(dioProvider);
    final response = await dio.getUri<String>(
      Uri.parse(url),
      options: Options(responseType: ResponseType.plain),
    );
    if (response.statusCode != null && response.statusCode! >= 400) {
      setState(() {
        _errorMessage = 'playlists.form_test_connection_failed'.tr(
          namedArgs: <String, String>{
            'message': 'HTTP ${response.statusCode}',
          },
        );
      });
      return;
    }
    final body = response.data ?? '';
    final channels = M3uParser.parse(body, 'preview');
    if (channels.isEmpty) {
      setState(() {
        _errorMessage = 'playlists.form_local_file_no_channels'.tr();
      });
      return;
    }
    setState(() {
      _verifiedMessage = 'playlists.form_test_connection_m3u_count'.tr(
        namedArgs: <String, String>{'n': channels.length.toString()},
      );
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = _autoNameFallback();
      }
    });
  }

  String _humanError(Object e) {
    if (e is XtreamAuthException) return e.message;
    if (e is StalkerAuthException) return e.message;
    if (e is PlaylistParseException) return e.message;
    if (e is NetworkException) return e.message;
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code != null) return 'HTTP $code';
      return e.message ?? e.toString();
    }
    return e.toString();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!_canSave) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = GoRouter.of(context);
    final id = const Uuid().v4();

    try {
      late PlaylistSource source;
      switch (_tab) {
        case _SourceTab.xtream:
          source = PlaylistSource(
            id: id,
            name: _autoNameFallback(),
            kind: PlaylistKind.xtream,
            url: _urlCtrl.text.trim(),
            addedAt: DateTime.now(),
            username: _userCtrl.text.trim(),
            password: _passCtrl.text,
            epgUrl: _epgCtrl.text.trim().isEmpty
                ? null
                : _epgCtrl.text.trim(),
          );
        case _SourceTab.m3u:
          source = PlaylistSource(
            id: id,
            name: _autoNameFallback(),
            kind: PlaylistKind.m3u,
            url: _urlCtrl.text.trim(),
            addedAt: DateTime.now(),
            epgUrl: _epgCtrl.text.trim().isEmpty
                ? null
                : _epgCtrl.text.trim(),
          );
        case _SourceTab.file:
          // Persist the picked file into the documents directory and
          // reference its absolute path as the playlist `url`. We do
          // NOT inline the body — the content can balloon to 5 MB on
          // big providers and Hive is not the right place for that.
          final savedPath = await _saveLocalFileToAppStorage(
            id: id,
            sourceFile: _pickedFile!,
            content: _pickedFileContent!,
          );
          source = PlaylistSource(
            id: id,
            name: _autoNameFallback(),
            kind: PlaylistKind.m3u,
            url: savedPath,
            addedAt: DateTime.now(),
          );
        case _SourceTab.stalker:
          source = PlaylistSource(
            id: id,
            name: _autoNameFallback(),
            kind: PlaylistKind.stalker,
            url: _urlCtrl.text.trim(),
            addedAt: DateTime.now(),
            username: StalkerClient.normaliseMac(_macCtrl.text.trim()),
            password: _stalkerTimezone,
            epgUrl: _epgCtrl.text.trim().isEmpty
                ? null
                : _epgCtrl.text.trim(),
          );
      }

      await ref.read(playlistServiceProvider).add(source);
      ref
        ..invalidate(playlistsProvider)
        ..invalidate(allChannelsProvider);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'playlists.snack_added'
                .tr(namedArgs: <String, String>{'name': source.name}),
          ),
        ),
      );
      navigator.go('/live');
    } on XtreamAuthException catch (e) {
      _surfaceError(messenger, 'playlists.snack_auth_failed', e.message);
    } on StalkerAuthException catch (e) {
      _surfaceError(messenger, 'playlists.snack_stalker_failed', e.message);
    } on PlaylistParseException catch (e) {
      _surfaceError(messenger, 'playlists.snack_parse_failed', e.message);
    } on NetworkException catch (e) {
      _surfaceError(messenger, 'playlists.snack_network_failed', e.message);
    } on Object catch (e) {
      _surfaceError(messenger, 'playlists.snack_add_failed', e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _surfaceError(
    ScaffoldMessengerState messenger,
    String key,
    String message,
  ) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          key.tr(namedArgs: <String, String>{'message': message}),
        ),
      ),
    );
  }

  /// Copies the picked file into the documents directory under
  /// `playlists/<id>.<ext>` and returns the absolute path. Storing the
  /// path rather than the raw content keeps the database small and
  /// avoids a 5 MB string sitting in the row.
  Future<String> _saveLocalFileToAppStorage({
    required String id,
    required XFile sourceFile,
    required String content,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/playlists');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final ext = _extensionOf(sourceFile.name).toLowerCase();
    final safeExt = ext.isEmpty ? 'm3u' : ext;
    final dest = File('${dir.path}/$id.$safeExt');
    await dest.writeAsString(content);
    return dest.path;
  }

  // ---------------------------------------------------------------------------
  // Stalker probe (legacy — preserved behind the advanced toggle)
  // ---------------------------------------------------------------------------

  Future<void> _probeStalker() async {
    final url = _urlCtrl.text.trim();
    final mac = _macCtrl.text.trim();
    if (_validateUrl(url) != null) {
      setState(() {
        _errorMessage = 'playlists.form_stalker_probe_url_first'.tr();
      });
      return;
    }
    if (_validateMac(mac) != null) {
      setState(() {
        _errorMessage = 'playlists.form_stalker_probe_mac_first'.tr();
      });
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
      _verifiedMessage = null;
    });
    try {
      final client = StalkerClient(
        portalUrl: url,
        macAddress: mac,
        timezone: _stalkerTimezone,
        dio: ref.read(dioProvider),
      );
      await client.handshake();
      if (!mounted) return;
      setState(() {
        _verifiedMessage = 'playlists.form_stalker_probe_ok'.tr();
      });
    } on StalkerAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'playlists.form_stalker_probe_rejected'.tr(
          namedArgs: <String, String>{'message': e.message},
        );
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'playlists.form_stalker_probe_unreachable'.tr(
          namedArgs: <String, String>{'message': e.message},
        );
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'playlists.form_stalker_probe_failed'.tr(
          namedArgs: <String, String>{'message': e.toString()},
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: BrandColors.background,
      appBar: AppBar(
        backgroundColor: BrandColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'common.close'.tr(),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/playlists'),
        ),
        title: Text(
          'playlists.form_title'.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: DesignTokens.spaceM),
            child: SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: _canSave && !_busy ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.primary,
                  disabledBackgroundColor:
                      BrandColors.primary.withValues(alpha: 0.4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceM,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusS),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        'playlists.form_save'.tr(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AbsorbPointer(
          absorbing: _busy,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SourceTypeRow(
                    selected: _tab,
                    onSelect: _switchTab,
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  _InfoNote(text: _infoTextForTab(_tab)),
                  const SizedBox(height: DesignTokens.spaceM),
                  _formForTab(theme),
                  const SizedBox(height: DesignTokens.spaceM),
                  _NameField(
                    controller: _nameCtrl,
                    hint: _hintForName(),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_tab == _SourceTab.xtream ||
                      _tab == _SourceTab.m3u) ...<Widget>[
                    const SizedBox(height: DesignTokens.spaceM),
                    _TestConnectionButton(
                      testing: _testing,
                      verified: _verifiedMessage != null,
                      onTap: _testing ? null : _testConnection,
                    ),
                  ],
                  if (_verifiedMessage != null) ...<Widget>[
                    const SizedBox(height: DesignTokens.spaceM),
                    _SuccessBanner(message: _verifiedMessage!),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: DesignTokens.spaceM),
                    _ErrorBanner(message: _errorMessage!),
                  ],
                  const SizedBox(height: DesignTokens.spaceL),
                  _BottomInfoCard(tab: _tab),
                  const SizedBox(height: DesignTokens.spaceM),
                  _AdvancedExpander(
                    epgController: _epgCtrl,
                    showStalker: _tab == _SourceTab.stalker,
                    onSwitchToStalker: () => _switchTab(_SourceTab.stalker),
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _infoTextForTab(_SourceTab tab) {
    switch (tab) {
      case _SourceTab.xtream:
        return 'playlists.form_xtream_info'.tr();
      case _SourceTab.m3u:
        return 'playlists.form_m3u_info'.tr();
      case _SourceTab.file:
        return 'playlists.form_local_file_info'.tr();
      case _SourceTab.stalker:
        return 'playlists.form_field_stalker_portal_help'.tr();
    }
  }

  Widget _formForTab(ThemeData theme) {
    switch (_tab) {
      case _SourceTab.xtream:
        return _XtreamForm(
          urlController: _urlCtrl,
          userController: _userCtrl,
          passController: _passCtrl,
          showPassword: _showPassword,
          onTogglePassword: () =>
              setState(() => _showPassword = !_showPassword),
          onUrlChanged: (_) => setState(() {}),
          onUserChanged: (_) => setState(() {}),
          onPassChanged: (_) => setState(() {}),
          urlValidator: _validateXtreamServer,
          credValidator: _validateXtreamCreds,
        );
      case _SourceTab.m3u:
        return _M3uForm(
          urlController: _urlCtrl,
          onUrlChanged: (v) => setState(() {
            // Clear sample selection if the user edits the URL by hand.
            if (_selectedSampleId != null) {
              final preset = samplePlaylists.firstWhere(
                (p) => p.id == _selectedSampleId,
                orElse: () => samplePlaylists.first,
              );
              if (preset.url != v) _selectedSampleId = null;
            }
          }),
          urlValidator: _validateUrl,
          selectedSampleId: _selectedSampleId,
          onSampleTap: _onSamplePlaylistTap,
        );
      case _SourceTab.file:
        return _LocalFileForm(
          picking: _pickingFile,
          file: _pickedFile,
          format: _pickedFileFormat,
          sizeBytes: _pickedFileSizeBytes,
          channelCount: _pickedFileChannelCount,
          onPick: _pickLocalFile,
          onClear: _clearPickedFile,
          formatBytes: _formatBytes,
        );
      case _SourceTab.stalker:
        return _StalkerForm(
          urlController: _urlCtrl,
          macController: _macCtrl,
          timezone: _stalkerTimezone,
          timezones: _timezones,
          onTimezoneChanged: (v) => setState(() => _stalkerTimezone = v),
          urlValidator: _validateUrl,
          macValidator: _validateMac,
          onProbe: _busy ? null : _probeStalker,
          onUrlChanged: (_) => setState(() {}),
          onMacChanged: (_) => setState(() {}),
          discoveryPanel: _LocalDiscoveryPanel(
            onPick: (DiscoveredIptvServer s) {
              _urlCtrl.text = s.suggestedUrl;
              if (_nameCtrl.text.trim().isEmpty) {
                _nameCtrl.text = s.name;
              }
              setState(() {});
            },
          ),
        );
    }
  }
}

// =============================================================================
// 3-card source-type selector
// =============================================================================

class _SourceTypeRow extends StatelessWidget {
  const _SourceTypeRow({
    required this.selected,
    required this.onSelect,
  });

  final _SourceTab selected;
  final ValueChanged<_SourceTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _TypeCard(
            icon: Icons.flash_on_rounded,
            title: 'playlists.kind_xtream'.tr(),
            subtitle: 'playlists.form_kind_xtream_subtitle'.tr(),
            isActive: selected == _SourceTab.xtream,
            onTap: () => onSelect(_SourceTab.xtream),
          ),
        ),
        const SizedBox(width: DesignTokens.spaceS),
        Expanded(
          child: _TypeCard(
            icon: Icons.link_rounded,
            title: 'playlists.kind_m3u'.tr(),
            subtitle: 'playlists.form_kind_m3u_subtitle'.tr(),
            isActive: selected == _SourceTab.m3u,
            onTap: () => onSelect(_SourceTab.m3u),
          ),
        ),
        const SizedBox(width: DesignTokens.spaceS),
        Expanded(
          child: _TypeCard(
            icon: Icons.upload_file_rounded,
            title: 'playlists.form_kind_local_file'.tr(),
            subtitle: 'playlists.form_kind_local_file_subtitle'.tr(),
            isActive: selected == _SourceTab.file,
            onTap: () => onSelect(_SourceTab.file),
          ),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final borderColor = isActive
        ? BrandColors.primary
        : cs.outlineVariant.withValues(alpha: 0.5);
    final bg = isActive
        ? BrandColors.primary.withValues(alpha: 0.10)
        : BrandColors.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: Stack(
          children: <Widget>[
            AnimatedContainer(
              duration: DesignTokens.motionFast,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceS,
                vertical: DesignTokens.spaceM - 4,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusM),
                border: Border.all(
                  color: borderColor,
                  width: isActive ? 1.6 : 1.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    icon,
                    color: isActive
                        ? BrandColors.primary
                        : cs.onSurface.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: BrandColors.primary,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Info note (header line above each form)
// =============================================================================

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceS + 2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Xtream form
// =============================================================================

class _XtreamForm extends StatelessWidget {
  const _XtreamForm({
    required this.urlController,
    required this.userController,
    required this.passController,
    required this.showPassword,
    required this.onTogglePassword,
    required this.onUrlChanged,
    required this.onUserChanged,
    required this.onPassChanged,
    required this.urlValidator,
    required this.credValidator,
  });

  final TextEditingController urlController;
  final TextEditingController userController;
  final TextEditingController passController;
  final bool showPassword;
  final VoidCallback onTogglePassword;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onUserChanged;
  final ValueChanged<String> onPassChanged;
  final String? Function(String?) urlValidator;
  final String? Function(String?) credValidator;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextFormField(
          controller: urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onChanged: onUrlChanged,
          decoration: InputDecoration(
            labelText: 'playlists.form_field_xtream_server_label'.tr(),
            hintText: 'playlists.form_field_xtream_server_hint'.tr(),
          ),
          validator: urlValidator,
        ),
        const SizedBox(height: DesignTokens.spaceM),
        TextFormField(
          controller: userController,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onChanged: onUserChanged,
          decoration: InputDecoration(
            labelText: 'playlists.form_field_xtream_username_label'.tr(),
            hintText: 'username',
          ),
          validator: credValidator,
        ),
        const SizedBox(height: DesignTokens.spaceM),
        TextFormField(
          controller: passController,
          autocorrect: false,
          obscureText: !showPassword,
          textInputAction: TextInputAction.done,
          onChanged: onPassChanged,
          decoration: InputDecoration(
            labelText: 'playlists.form_field_xtream_password_label'.tr(),
            hintText: 'password',
            suffixIcon: IconButton(
              icon: Icon(
                showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: onTogglePassword,
            ),
          ),
          validator: credValidator,
        ),
      ],
    );
  }
}

// =============================================================================
// M3U form (URL field + sample-playlist rail)
// =============================================================================

class _M3uForm extends StatelessWidget {
  const _M3uForm({
    required this.urlController,
    required this.onUrlChanged,
    required this.urlValidator,
    required this.selectedSampleId,
    required this.onSampleTap,
  });

  final TextEditingController urlController;
  final ValueChanged<String> onUrlChanged;
  final String? Function(String?) urlValidator;
  final String? selectedSampleId;
  final ValueChanged<SamplePlaylistPreset> onSampleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          controller: urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onChanged: onUrlChanged,
          decoration: InputDecoration(
            labelText: 'playlists.form_field_m3u_url_label'.tr(),
            hintText: 'playlists.form_field_m3u_url_hint'.tr(),
          ),
          validator: urlValidator,
        ),
        const SizedBox(height: DesignTokens.spaceL),
        Text(
          'playlists.form_sample_playlists_title'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Text(
          'playlists.form_sample_playlists_help'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant
                .withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceS),
        for (final preset in samplePlaylists)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spaceS),
            child: SamplePlaylistChip(
              preset: preset,
              selected: selectedSampleId == preset.id,
              onTap: onSampleTap,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Local file form — picker tile + 3-cell stat row
// =============================================================================

class _LocalFileForm extends StatelessWidget {
  const _LocalFileForm({
    required this.picking,
    required this.file,
    required this.format,
    required this.sizeBytes,
    required this.channelCount,
    required this.onPick,
    required this.onClear,
    required this.formatBytes,
  });

  final bool picking;
  final XFile? file;
  final String? format;
  final int? sizeBytes;
  final int? channelCount;
  final Future<void> Function() onPick;
  final VoidCallback onClear;
  final String Function(int bytes) formatBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: picking ? null : onPick,
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            child: Container(
              constraints: const BoxConstraints(minHeight: 88),
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              decoration: BoxDecoration(
                color: BrandColors.surface,
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusM),
                border: Border.all(
                  color: file != null
                      ? BrandColors.primary
                      : BrandColors.primary.withValues(alpha: 0.45),
                  width: file != null ? 1.4 : 1.0,
                  style: file != null
                      ? BorderStyle.solid
                      : BorderStyle.solid,
                ),
              ),
              child: picking
                  ? Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              BrandColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spaceM),
                        Text(
                          'playlists.form_field_local_file_picking'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    )
                  : file == null
                      ? _IdleFileTile(theme: theme)
                      : _PickedFileTile(
                          file: file!,
                          format: format ?? 'M3U',
                          sizeBytes: sizeBytes ?? 0,
                          formatBytes: formatBytes,
                          onClear: onClear,
                          theme: theme,
                        ),
            ),
          ),
        ),
        if (file != null && channelCount != null) ...<Widget>[
          const SizedBox(height: DesignTokens.spaceM),
          _FileStatsRow(
            channels: channelCount!,
            sizeLabel:
                sizeBytes != null ? formatBytes(sizeBytes!) : '-',
            format: format ?? 'M3U',
          ),
        ],
      ],
    );
  }
}

class _IdleFileTile extends StatelessWidget {
  const _IdleFileTile({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: BrandColors.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.folder_open_rounded,
            color: BrandColors.primary,
            size: 28,
          ),
        ),
        const SizedBox(width: DesignTokens.spaceM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'playlists.form_field_local_file_pick'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'playlists.form_field_local_file_help'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          color: cs.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _PickedFileTile extends StatelessWidget {
  const _PickedFileTile({
    required this.file,
    required this.format,
    required this.sizeBytes,
    required this.formatBytes,
    required this.onClear,
    required this.theme,
  });

  final XFile file;
  final String format;
  final int sizeBytes;
  final String Function(int bytes) formatBytes;
  final VoidCallback onClear;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: BrandColors.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(DesignTokens.radiusS),
            border: Border.all(
              color: BrandColors.primary.withValues(alpha: 0.55),
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.description_rounded,
            color: BrandColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: DesignTokens.spaceM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: BrandColors.primary.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusS),
                    ),
                    child: Text(
                      format,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: BrandColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceS),
                  Text(
                    formatBytes(sizeBytes),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'playlists.form_field_local_file_clear'.tr(),
          icon: const Icon(Icons.cancel_rounded),
          color: cs.onSurfaceVariant,
          onPressed: onClear,
        ),
      ],
    );
  }
}

class _FileStatsRow extends StatelessWidget {
  const _FileStatsRow({
    required this.channels,
    required this.sizeLabel,
    required this.format,
  });

  final int channels;
  final String sizeLabel;
  final String format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: DesignTokens.spaceM,
      ),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _StatCell(
                icon: Icons.tv_rounded,
                value: '$channels',
                label: 'playlists.form_field_local_file_channels'.tr(),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant
                  .withValues(alpha: 0.5),
            ),
            Expanded(
              child: _StatCell(
                icon: Icons.storage_rounded,
                value: sizeLabel,
                label: 'playlists.form_field_local_file_size'.tr(),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant
                  .withValues(alpha: 0.5),
            ),
            Expanded(
              child: _StatCell(
                icon: Icons.description_rounded,
                value: format,
                label: 'playlists.form_field_local_file_format'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          icon,
          color: BrandColors.primary,
          size: 18,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Stalker form (preserved from pre-port)
// =============================================================================

class _StalkerForm extends StatelessWidget {
  const _StalkerForm({
    required this.urlController,
    required this.macController,
    required this.timezone,
    required this.timezones,
    required this.onTimezoneChanged,
    required this.urlValidator,
    required this.macValidator,
    required this.onProbe,
    required this.onUrlChanged,
    required this.onMacChanged,
    required this.discoveryPanel,
  });

  final TextEditingController urlController;
  final TextEditingController macController;
  final String timezone;
  final List<String> timezones;
  final ValueChanged<String> onTimezoneChanged;
  final String? Function(String?) urlValidator;
  final String? Function(String?) macValidator;
  final VoidCallback? onProbe;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onMacChanged;
  final Widget discoveryPanel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextFormField(
          controller: urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onChanged: onUrlChanged,
          decoration: InputDecoration(
            labelText: 'playlists.form_field_stalker_portal_label'.tr(),
            hintText: 'playlists.form_field_stalker_portal_hint'.tr(),
            helperText: 'playlists.form_field_stalker_portal_help'.tr(),
          ),
          validator: urlValidator,
        ),
        const SizedBox(height: DesignTokens.spaceS),
        discoveryPanel,
        const SizedBox(height: DesignTokens.spaceM),
        TextFormField(
          controller: macController,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          onChanged: onMacChanged,
          inputFormatters: <TextInputFormatter>[
            _MacAddressFormatter(),
          ],
          decoration: InputDecoration(
            labelText: 'playlists.form_field_mac_label'.tr(),
            hintText: 'playlists.form_field_mac_hint'.tr(),
          ),
          validator: macValidator,
        ),
        const SizedBox(height: DesignTokens.spaceM),
        DropdownButtonFormField<String>(
          initialValue: timezone,
          decoration: InputDecoration(
            labelText: 'playlists.form_field_timezone_label'.tr(),
          ),
          items: <DropdownMenuItem<String>>[
            for (final tz in timezones)
              DropdownMenuItem<String>(
                value: tz,
                child: Text(tz),
              ),
          ],
          onChanged: (String? v) {
            if (v == null) return;
            onTimezoneChanged(v);
          },
        ),
        const SizedBox(height: DesignTokens.spaceM),
        OutlinedButton.icon(
          onPressed: onProbe,
          icon: const Icon(Icons.search_rounded),
          label: Text('playlists.form_stalker_probe'.tr()),
        ),
      ],
    );
  }
}

// =============================================================================
// Name field
// =============================================================================

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textInputAction: TextInputAction.next,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'playlists.form_field_name_label'.tr(),
        hintText: hint,
      ),
    );
  }
}

// =============================================================================
// Test connection / banners
// =============================================================================

class _TestConnectionButton extends StatelessWidget {
  const _TestConnectionButton({
    required this.testing,
    required this.verified,
    required this.onTap,
  });

  final bool testing;
  final bool verified;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verified ? BrandColors.success : BrandColors.primary;
    final icon = verified
        ? Icons.check_circle_outline_rounded
        : Icons.wifi_rounded;
    final label = testing
        ? 'playlists.form_test_connecting'.tr()
        : verified
            ? 'playlists.form_test_connection_ok'.tr()
            : 'playlists.form_test_connection'.tr();

    return SizedBox(
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
              border: Border.all(
                color: color.withValues(alpha: 0.55),
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (testing)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  )
                else
                  Icon(icon, size: 18, color: color),
                const SizedBox(width: DesignTokens.spaceS),
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
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

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: BrandColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: BrandColors.success.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.check_circle_outline_rounded,
            color: BrandColors.success,
            size: 20,
          ),
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: BrandColors.success,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: BrandColors.error.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: BrandColors.error,
            size: 20,
          ),
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: BrandColors.error,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Bottom info card (bullets per source type)
// =============================================================================

class _BottomInfoCard extends StatelessWidget {
  const _BottomInfoCard({required this.tab});

  final _SourceTab tab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bullets = _bulletsForTab(tab);

    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final line in bullets)
            Padding(
              padding: EdgeInsets.only(
                bottom: bullets.last == line
                    ? 0
                    : DesignTokens.spaceXs + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: BrandColors.primary,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceS),
                  Expanded(
                    child: Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _bulletsForTab(_SourceTab tab) {
    switch (tab) {
      case _SourceTab.xtream:
        return 'playlists.form_info_xtream_bullets'.tr().split('\n');
      case _SourceTab.m3u:
        return 'playlists.form_info_m3u_bullets'.tr().split('\n');
      case _SourceTab.file:
        return 'playlists.form_info_local_file_bullets'.tr().split('\n');
      case _SourceTab.stalker:
        return <String>[
          'playlists.form_field_stalker_portal_help'.tr(),
        ];
    }
  }
}

// =============================================================================
// Advanced expander (EPG URL + Stalker pivot)
// =============================================================================

class _AdvancedExpander extends StatelessWidget {
  const _AdvancedExpander({
    required this.epgController,
    required this.showStalker,
    required this.onSwitchToStalker,
  });

  final TextEditingController epgController;
  final bool showStalker;
  final VoidCallback onSwitchToStalker;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: ExpansionTile(
        title: Text('playlists.form_advanced'.tr()),
        childrenPadding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spaceS,
        ),
        children: <Widget>[
          TextFormField(
            controller: epgController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'playlists.form_field_epg_label'.tr(),
              hintText: 'playlists.form_field_epg_hint'.tr(),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceM),
          if (!showStalker)
            OutlinedButton.icon(
              onPressed: onSwitchToStalker,
              icon: const Icon(Icons.dns_outlined),
              label: Text('playlists.kind_stalker'.tr()),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// MAC address formatter (preserved)
// =============================================================================

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

// =============================================================================
// Local discovery panel (preserved from pre-port)
// =============================================================================

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
        title: Text('playlists.discovery_title'.tr()),
        subtitle: discovery.when(
          data: (List<DiscoveredIptvServer> values) {
            if (values.isEmpty) {
              return Text('playlists.discovery_subtitle_empty'.tr());
            }
            return Text(
              'playlists.discovery_subtitle_count'.tr(
                namedArgs: <String, String>{'n': values.length.toString()},
              ),
            );
          },
          loading: () => Text('playlists.discovery_loading'.tr()),
          error: (Object _, StackTrace __) =>
              Text('playlists.discovery_failed'.tr()),
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
                          'playlists.discovery_help'.tr(),
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
