import SwiftUI

struct QuickTerminalTabItemView: View {
    @ObservedObject var tab: QuickTerminalTab
    let isSelected: Bool
    let isSingleTab: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundColor(isHovered ? .primary : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovered || isSelected ? 1 : 0)
            .animation(.easeInOut, value: isHovered || isSelected)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected && !isSingleTab
                        ? Color(NSColor.selectedContentBackgroundColor)
                        : (isHovered ? Color(NSColor.gridColor) : Color.clear))
        )
        .padding(.horizontal, 2)
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
