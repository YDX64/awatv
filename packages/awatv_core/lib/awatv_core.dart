/// AWAtv core domain logic.
///
/// Pure-Dart package. No Flutter dependencies. Provides:
/// - Models for playlists, channels, VOD, series, EPG.
/// - Parsers for M3U/M3U8 and Xtream Codes API.
/// - Services for playlists, metadata (TMDB), EPG, favorites, history.
/// - Hive-backed storage adapters.
library;

// Clients
export 'src/clients/epg_client.dart';
export 'src/clients/logos_fallback.dart';
export 'src/clients/opensubtitles_client.dart';
export 'src/clients/provider_intel.dart';
export 'src/clients/stalker_client.dart';
export 'src/clients/tmdb_client.dart';
export 'src/clients/xtream_client.dart';
// Models
export 'src/models/catchup_programme.dart';
export 'src/models/channel.dart';
export 'src/models/download_task.dart';
export 'src/models/epg_programme.dart';
export 'src/models/episode.dart';
export 'src/models/history_entry.dart';
export 'src/models/playlist_source.dart';
export 'src/models/recording_task.dart';
export 'src/models/series_item.dart';
export 'src/models/subtitle_settings.dart';
export 'src/models/tmdb_credits.dart';
export 'src/models/tmdb_models.dart';
export 'src/models/vod_item.dart';
// Parsers
export 'src/parsers/m3u_parser.dart';
export 'src/parsers/xmltv_parser.dart';
// Services
export 'src/services/catchup_service.dart';
export 'src/services/downloads_service.dart';
export 'src/services/epg_service.dart';
export 'src/services/favorites_service.dart';
export 'src/services/history_service.dart';
export 'src/services/metadata_service.dart';
export 'src/services/playlist_service.dart';
export 'src/services/recording_service.dart';
export 'src/services/reminders_service.dart';
export 'src/services/subtitles_service.dart';
export 'src/services/watchlist_service.dart';
// Storage
export 'src/storage/awatv_storage.dart';
export 'src/utils/awatv_exceptions.dart';
// Utils
export 'src/utils/awatv_logger.dart';
