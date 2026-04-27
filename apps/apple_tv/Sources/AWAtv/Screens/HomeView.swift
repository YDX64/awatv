import SwiftUI

/// Top-level home shell. The actual sidebar TabView lives in `ContentView`
/// so it has direct access to the environment stores; `HomeView` exists for
/// folder-structure parity with the spec (and to keep room for an
/// "Editor's Picks" landing page in a later phase).
struct HomeView: View {
    var body: some View {
        ContentView()
    }
}
