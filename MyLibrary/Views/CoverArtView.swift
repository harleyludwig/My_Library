import SwiftUI

struct CoverArtView: View {
    let coverURL: String
    let title: String
    var width: CGFloat = 70
    var height: CGFloat = 105

    var body: some View {
        Group {
            if let url = URL(string: coverURL), !coverURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackCover
                    }
                }
            } else {
                fallbackCover
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 3)
    }

    private var fallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.75), .green.opacity(0.75), .orange.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(String(title.prefix(20)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 6)
            }
        }
    }
}
