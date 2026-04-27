import SwiftUI
import AVKit

/// Wraps `AVPlayerViewController` for SwiftUI. On tvOS the system player
/// gives us:
/// - Built-in Siri-Remote scrubbing, seek, jump-back/forward
/// - Closed-caption picker
/// - Audio track selector (multi-language Xtream streams light up
///   automatically)
/// - "Up next" recommendations slot we can populate later
///
/// We deliberately let AVPlayerViewController own the chrome rather than
/// building custom controls — Apple's controls are battle-tested and
/// users expect them on Apple TV.
struct PlayerView: View {
    @Environment(PlayerStore.self) private var playerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BrandColors.background.ignoresSafeArea()
            if let media = playerStore.media,
               let url = URL(string: media.streamUrl)
            {
                AVPlayerControllerRepresentable(url: url, title: media.title, subtitle: media.subtitle)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 80))
                        .foregroundStyle(BrandColors.pink)
                    Text("Nothing to play")
                        .font(AWATypography.title2)
                        .foregroundStyle(BrandColors.textPrimary)
                }
            }
        }
        .onDisappear {
            playerStore.dismiss()
        }
    }
}

/// `UIViewControllerRepresentable` bridge for AVPlayerViewController.
private struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let url: URL
    let title: String
    let subtitle: String?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)

        // Buffer aggressively for smoother HLS-over-iffy-IPTV playback.
        // Matches the "smart buffering" requirement from CLAUDE.md.
        player.automaticallyWaitsToMinimizeStalling = true

        let metadata = makeMetadata()
        if let asset = player.currentItem?.asset as? AVURLAsset {
            asset.resourceLoader.preloadsEligibleContentKeys = true
        }

        // Attach navigation metadata so the AVPlayerViewController shows the
        // title in the system Now-Playing UI.
        let item = player.currentItem
        item?.externalMetadata = metadata

        let controller = AVPlayerViewController()
        controller.player = player
        // Picture-in-picture isn't available on tvOS — explicitly off.
        controller.allowsPictureInPicturePlayback = false
        controller.modalPresentationStyle = .fullScreen
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No-op — the AVPlayer manages its own state.
    }

    static func dismantleUIViewController(
        _ uiViewController: AVPlayerViewController,
        coordinator: ()
    ) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }

    private func makeMetadata() -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        items.append(metadataItem(identifier: .commonIdentifierTitle, value: title))
        if let subtitle, !subtitle.isEmpty {
            items.append(metadataItem(identifier: .iTunesMetadataTrackSubTitle, value: subtitle))
        }
        return items
    }

    private func metadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        // AVPlayerItem.externalMetadata accepts AVMetadataItem; the mutable
        // subclass is fine to upcast directly.
        return item
    }
}
