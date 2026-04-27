import SwiftUI

/// AWAtv — native SwiftUI tvOS app entry point.
///
/// Mirrors the Flutter app's responsibilities: live channels, VOD, series,
/// search, settings — but as a separate native binary. Phase 4 of the AWAtv
/// roadmap; eventual integration with the Phase 5 backend will replace the
/// in-app `XtreamClient` with REST calls into `awatv_core`.
@main
struct AWAtvApp: App {
    @State private var playlistStore = PlaylistStore()
    @State private var playerStore = PlayerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(playlistStore)
                .environment(playerStore)
                .preferredColorScheme(.dark)
                .tint(BrandColors.accent)
        }
    }
}
