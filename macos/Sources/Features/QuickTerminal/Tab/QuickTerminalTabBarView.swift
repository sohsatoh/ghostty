import SwiftUI

struct QuickTerminalTabBarView: View {
    @ObservedObject var tabManager: QuickTerminalTabManager
    let tabBarPosition: QuickTerminalTabBarPosition
    let tabBarWidth: CGFloat
    let tabWrap: Bool

    var body: some View {
        switch tabBarPosition {
        case .top:
            horizontalTabBar
        case .left, .right:
            verticalTabBar
        case .hidden:
            EmptyView()
        }
    }

    private var horizontalTabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabItem(tab: tab, index: index)
                    Divider()
                        .background(Color(NSColor.separatorColor))
                }
            }

            newTabButton
        }
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var verticalTabBar: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabItem(tab: tab, index: index)
                        Divider()
                            .background(Color(NSColor.separatorColor))
                    }
                }
            }

            Divider()
                .background(Color(NSColor.separatorColor))

            newTabButton
                .frame(height: 32)
        }
        .frame(width: tabBarWidth)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func tabItem(tab: QuickTerminalTab, index: Int) -> some View {
        QuickTerminalTabItemView(
            tab: tab,
            tabNumber: index + 1,
            isHighlighted: tab.isActive,
            isVertical: tabBarPosition.isVertical,
            tabWrap: tabWrap,
            onSelect: { tabManager.selectTab(tab) },
            onClose: { tabManager.closeTab(tab) }
        )
        .contextMenu {
            Button("Close Tab") {
                tabManager.closeTab(tab)
            }
            Button("Close Other Tabs") {
                tabManager.tabs.forEach { otherTab in
                    if otherTab.id != tab.id {
                        tabManager.closeTab(otherTab)
                    }
                }
            }
        }
        .onDrag {
            tabManager.draggedTab = tab
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: QuickTerminalTabDropDelegate(
                item: tab,
                tabManager: tabManager,
                currentTab: tabManager.draggedTab
            )
        )
    }

    private var newTabButton: some View {
        Image(systemName: "plus")
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 8)
            .frame(width: tabBarPosition.isVertical ? nil : 50)
            .frame(maxWidth: tabBarPosition.isVertical ? .infinity : nil)
            .contentShape(Rectangle())
            .onTapGesture {
                tabManager.newTab()
            }
            .buttonStyle(PlainButtonStyle())
            .help("New Tab")
    }
}

struct QuickTerminalTabDropDelegate: DropDelegate {
    let item: QuickTerminalTab
    let tabManager: QuickTerminalTabManager
    let currentTab: QuickTerminalTab?

    func performDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let currentTab = currentTab,
            let from = tabManager.tabs.firstIndex(where: { $0.id == currentTab.id }),
            let to = tabManager.tabs.firstIndex(where: { $0.id == item.id })
        else { return }

        if tabManager.tabs[to].id != currentTab.id {
            tabManager.tabs.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to)
        }
    }
}
