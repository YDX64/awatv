import SwiftUI

/// Settings screen — playlist management is the only Phase 4 feature here.
/// Future iterations will add theme controls, parental PIN, premium status.
struct SettingsView: View {
    @Environment(PlaylistStore.self) private var playlistStore
    @State private var isAddingSource: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    header

                    sourcesSection

                    aboutSection
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            }
            .background(BrandColors.background.ignoresSafeArea())
            .sheet(isPresented: $isAddingSource) {
                AddPlaylistSheet { source in
                    isAddingSource = false
                    Task { await playlistStore.add(source) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(AWATypography.display)
                .foregroundStyle(BrandColors.textPrimary)
            Text("Manage your playlists, accounts and preferences.")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Playlists")
                    .font(AWATypography.title2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button {
                    isAddingSource = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(AWATypography.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(BrandColors.primaryLight)
            }

            if playlistStore.sources.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(BrandColors.primaryLight)
                    Text("No playlists yet")
                        .font(AWATypography.headline)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text("Add an M3U URL or Xtream account to start streaming.")
                        .font(AWATypography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 24))
            } else {
                ForEach(playlistStore.sources) { source in
                    SourceRow(source: source) {
                        Task { await playlistStore.refresh(sourceId: source.id) }
                    } onRemove: {
                        playlistStore.remove(source)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(AWATypography.title2)
                .foregroundStyle(BrandColors.textPrimary)
            Text("AWAtv tvOS · Version 0.1.0")
                .font(AWATypography.body)
                .foregroundStyle(BrandColors.textSecondary)
            Text("Native SwiftUI client. Eventual integration with awatv_core via REST will land in Phase 5.")
                .font(AWATypography.callout)
                .foregroundStyle(BrandColors.textMuted)
                .frame(maxWidth: 1200, alignment: .leading)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct SourceRow: View {
    let source: PlaylistSource
    var onRefresh: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: source.kind == .xtream ? "antenna.radiowaves.left.and.right" : "link")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(BrandColors.accent)
                .frame(width: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(source.name)
                    .font(AWATypography.headline)
                    .foregroundStyle(BrandColors.textPrimary)
                Text(source.url)
                    .font(AWATypography.caption)
                    .foregroundStyle(BrandColors.textMuted)
                    .lineLimit(1)
                if let lastSync = source.lastSyncAt {
                    Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(AWATypography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }
            Spacer()

            Button {
                onRefresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
        .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct AddPlaylistSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case xtream = "Xtream Codes"
        case m3u = "M3U / M3U8 URL"
        var id: String { rawValue }
    }

    var onAdd: (PlaylistSource) -> Void

    @State private var mode: Mode = .xtream
    @State private var name: String = ""
    @State private var server: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var url: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Picker("Type", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    labeledField("Display name") {
                        TextField("e.g. Home Xtream", text: $name)
                    }

                    if mode == .xtream {
                        labeledField("Server URL") {
                            TextField("https://example.com:8080", text: $server)
                        }
                        labeledField("Username") {
                            TextField("Username", text: $username)
                        }
                        labeledField("Password") {
                            SecureField("Password", text: $password)
                        }
                    } else {
                        labeledField("Playlist URL") {
                            TextField("https://example.com/list.m3u", text: $url)
                        }
                    }

                    HStack(spacing: 18) {
                        Button("Cancel", role: .cancel) { dismiss() }
                            .buttonStyle(.bordered)

                        Button("Save", action: save)
                            .buttonStyle(.borderedProminent)
                            .tint(BrandColors.accent)
                            .disabled(!isValid)
                    }
                    .padding(.top, 16)
                }
                .padding(60)
            }
            .background(BrandColors.background.ignoresSafeArea())
            .navigationTitle("Add playlist")
        }
    }

    @ViewBuilder
    private func labeledField<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(BrandColors.textMuted)
            field()
                .font(AWATypography.body)
                .padding(16)
                .background(BrandColors.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func save() {
        let source: PlaylistSource
        switch mode {
        case .xtream:
            source = PlaylistSource(
                name: name.isEmpty ? "Xtream" : name,
                kind: .xtream,
                url: server,
                username: username,
                password: password
            )
        case .m3u:
            source = PlaylistSource(
                name: name.isEmpty ? "M3U Playlist" : name,
                kind: .m3u,
                url: url
            )
        }
        onAdd(source)
    }

    private var isValid: Bool {
        switch mode {
        case .xtream:
            return !server.isEmpty && !username.isEmpty && !password.isEmpty
        case .m3u:
            return !url.isEmpty
        }
    }
}
