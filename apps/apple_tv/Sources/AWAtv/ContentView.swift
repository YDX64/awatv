import SwiftUI

/// Root container — five top-level sections in a sidebar-style TabView.
///
/// On tvOS 17+ the sidebar adaptable style yields a focusable left rail that
/// the Siri remote can D-pad through. SwiftUI's focus engine handles ring
/// animations, scroll-into-view and remembered focus per tab automatically.
struct ContentView: View {
    @Environment(PlaylistStore.self) private var playlistStore

    var body: some View {
        TabView {
            LiveChannelsView()
                .tabItem {
                    Label("Live", systemImage: "tv.inset.filled")
                }

            MoviesView()
                .tabItem {
                    Label("Movies", systemImage: "film.stack")
                }

            SeriesView()
                .tabItem {
                    Label("Series", systemImage: "play.rectangle.on.rectangle")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .background(BrandColors.background.ignoresSafeArea())
        .task {
            await playlistStore.bootstrap()
        }
    }
}

#Preview {
    ContentView()
        .environment(PlaylistStore())
        .environment(PlayerStore())
}
