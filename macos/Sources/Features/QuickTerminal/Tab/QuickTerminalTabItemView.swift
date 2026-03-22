import SwiftUI

struct QuickTerminalTabItemView: View {
    @ObservedObject var tab: QuickTerminalTab
    let tabNumber: Int
    let isHighlighted: Bool
    let isVertical: Bool
    let tabWrap: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var animationOffset: CGFloat = 0

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

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .foregroundColor(isHighlighted ? .primary : .secondary)
                    .lineLimit(tabWrap ? nil : 1)
                    .truncationMode(.tail)

                if let displayPwd = tab.displayPwd {
                    Text(displayPwd)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, tabWrap ? 6 : 0)
        .frame(minHeight: tab.displayPwd != nil ? 44 : 32)
        .frame(maxWidth: isVertical ? .infinity : nil)
        .background(
            Rectangle()
                .fill(
                    isHighlighted
                        ? Color(NSColor.controlBackgroundColor)
                        : (isHovered ? Color(NSColor.underPageBackgroundColor) : Color(NSColor.windowBackgroundColor)))
        )
        .overlay(alignment: .bottom) {
            if tab.commandRunning {
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * 0.3, height: 2)
                        .offset(x: geometry.size.width * 0.7 * animationOffset)
                }
                .frame(height: 2)
                .onAppear {
                    animationOffset = 0
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        animationOffset = 1.0
                    }
                }
                .onDisappear {
                    animationOffset = 0
                }
            }
        }
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
