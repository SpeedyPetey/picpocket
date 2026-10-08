import SwiftUI

enum Layout {
    static let panelHeight: CGFloat = 380
    static let cardWidth: CGFloat = 150
    static let capacity = 6

    static func cardCenter(index: Int) -> CGPoint {
        CGPoint(x: 100 + CGFloat(index % 2) * 180,
                y: 94 + CGFloat(index / 2) * 108)
    }

    @MainActor static func hoveredID(in items: [Pegged], at point: CGPoint) -> UUID? {
        for (index, item) in items.reversed().enumerated() where !item.falling && !item.flying {
            let center = cardCenter(index: index)
            let size = PeggedView.cardSize(for: item.thumb.size)
            let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                               width: size.width, height: size.height)
            if frame.contains(point) { return item.id }
        }
        return nil
    }

    static func hotZone(in screen: CGRect) -> CGRect {
        CGRect(x: screen.maxX - 40, y: screen.minY, width: 40, height: 40)
    }
}

struct LineView: View {
    @ObservedObject var line: Line
    var pocketStats: PocketStats
    var onSettings: () -> Void
    @State private var showingStats = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22).fill(.regularMaterial)
            if line.items.isEmpty {
                Text(L("Take a screenshot to add it here", "Haz una captura para añadirla aquí"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.panelHeight, height: Layout.panelHeight)
            }
            ForEach(Array(line.items.reversed().enumerated()), id: \.element.id) { index, item in
                PeggedView(item: item, line: line)
                    .position(Layout.cardCenter(index: index))
                    .allowsHitTesting(!item.falling)
                    .animation(.easeOut(duration: 0.2), value: index)
            }
        }
        .frame(width: Layout.panelHeight, height: Layout.panelHeight)
        .overlay(alignment: .top) {
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingStats.toggle() }
                } label: {
                    Image(nsImage: PocketIcon.image)
                        .renderingMode(.template)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Your pocket report", "El informe de tu bolsillo"))
                .accessibilityLabel(L("Your pocket report", "El informe de tu bolsillo"))
                Text(L("Your PicPocket", "Tu PicPocket"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Pocket settings", "Ajustes del bolsillo"))
                .accessibilityLabel(L("Pocket settings", "Ajustes del bolsillo"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .overlay(alignment: .topLeading) {
            if showingStats {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingStats = false }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Pocket report", "Informe del bolsillo"))
                            .font(.system(size: 12, weight: .semibold))
                        let count = pocketStats.count()
                        Text(count == 1
                             ? L("1 screenshot pocketed today. Nice catch!", "1 captura en tu bolsillo hoy. ¡Buen hallazgo!")
                             : L("\(count) screenshots pocketed today. \(count == 0 ? "Ready for a little collecting?" : "Quite the collection!")",
                                 "\(count) capturas en tu bolsillo hoy."))
                            .font(.system(size: 12))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .frame(maxWidth: 290, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1)))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 44)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .onChange(of: line.revealed) { _, revealed in
            if !revealed { showingStats = false }
        }
        .opacity(line.revealed ? 1 : 0)
        .offset(y: line.revealed ? 0 : 16)
        .animation(.easeOut(duration: 0.18), value: line.revealed)
    }
}
