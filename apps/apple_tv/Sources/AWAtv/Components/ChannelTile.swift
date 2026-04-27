import SwiftUI

/// 16:9 horizontal tile used on the live channels grid.
///
/// Smaller than the poster card and arranged in wider columns since logos
/// tend to be square or 16:9. Uses the same focus + scale + glow language.
struct ChannelTile: View {
    let channel: Channel
    var nowPlayingTitle: String?
    var onSelect: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isFocused ? BrandColors.surfaceFocused : BrandColors.surface)

                    if let urlString = channel.logoUrl,
                       let url = URL(string: urlString)
                    {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().tint(BrandColors.primaryLight)
                            case .success(let image):
                                image.resizable().scaledToFit().padding(24)
                            case .failure:
                                fallbackArt
                            @unknown default:
                                fallbackArt
                            }
                        }
                    } else {
                        fallbackArt
                    }

                    VStack {
                        HStack {
                            liveBadge
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                }
                .frame(width: 360, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isFocused ? BrandColors.accent : .white.opacity(0.06), lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(AWATypography.headline)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)

                    if let nowPlayingTitle, !nowPlayingTitle.isEmpty {
                        Text(nowPlayingTitle)
                            .font(AWATypography.caption)
                            .foregroundStyle(BrandColors.textMuted)
                            .lineLimit(1)
                    } else if let group = channel.groups.first {
                        Text(group)
                            .font(AWATypography.caption)
                            .foregroundStyle(BrandColors.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }
            .padding(8)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
        .focusGlow(isFocused, radius: 28)
    }

    private var fallbackArt: some View {
        ZStack {
            BrandColors.heroGradient.opacity(0.18)
            Text(channelInitials)
                .font(AWATypography.title1)
                .foregroundStyle(BrandColors.textPrimary.opacity(0.85))
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(BrandColors.accent)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
            Text("LIVE")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var channelInitials: String {
        let words = channel.name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}
