import SwiftUI

struct QuickTerminalTabItemView: View {
    @ObservedObject var tab: QuickTerminalTab
    let tabNumber: Int
    let isHighlighted: Bool
    let isVertical: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundColor(isHovered ? .primary : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut, value: isHovered)

            Text("\(tabNumber)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isHighlighted ? .primary : .secondary)

            Text(tab.title)
                .foregroundColor(isHighlighted ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .frame(maxWidth: isVertical ? .infinity : nil)
        .background(
            Rectangle()
                .fill(
                    isHighlighted
                        ? Color(NSColor.controlBackgroundColor)
                        : (isHovered ? Color(NSColor.underPageBackgroundColor) : Color(NSColor.windowBackgroundColor)))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(
            perform: {
                DispatchQueue.main.async {
                    onSelect()
                }
            })
    }
}
