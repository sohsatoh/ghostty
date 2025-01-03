import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabManager: QuickTerminalTabManager
    @GestureState private var isDragging: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabManager.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isSelected: tab.isActive,
                            onSelect: { tabManager.selectTab(tab) },
                            onClose: { tabManager.closeTab(tab) }
                        )
                        .onDrag {
                            tabManager.draggedTab = tab
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: TabDropDelegate(
                                item: tab,
                                tabManager: tabManager,
                                currentTab: tabManager.draggedTab
                            )
                        )
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
            )

            Divider()

            Image(systemName: "plus")
                .foregroundColor(.gray)
                .padding(.horizontal, 8)
                .frame(width: 50)
                .contentShape(Rectangle())  // Make the entire frame clickable
                .onTapGesture {
                    tabManager.addNewTab()
                }
                .buttonStyle(PlainButtonStyle())
                .help("New Tab")
        }
        .frame(height: 32)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TabDropDelegate: DropDelegate {
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
