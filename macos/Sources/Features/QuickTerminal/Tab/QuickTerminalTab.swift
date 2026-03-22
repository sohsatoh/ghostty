import Cocoa
import Combine

class QuickTerminalTab: ObservableObject, Identifiable {
    let id = UUID()
    var surfaceTree: SplitTree<Ghostty.SurfaceView>
    @Published var title: String
    @Published var pwd: String?
    @Published var isActive: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(surfaceTree: SplitTree<Ghostty.SurfaceView>, title: String = "Terminal") {
        self.surfaceTree = surfaceTree

        // Get the first surface view to extract the title and pwd
        if let firstView = surfaceTree.first {
            self.title = firstView.title
            self.pwd = firstView.pwd

            // Subscribe to title changes
            firstView.$title
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newTitle in
                    self?.title = newTitle
                }
                .store(in: &cancellables)

            // Subscribe to pwd changes
            firstView.$pwd
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newPwd in
                    self?.pwd = newPwd
                }
                .store(in: &cancellables)
        } else {
            self.title = title
        }
    }

    /// Returns pwd with home directory shortened to `~`
    var displayPwd: String? {
        guard let pwd = pwd else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if pwd.hasPrefix(home) {
            let relative = String(pwd.dropFirst(home.count))
            return relative.isEmpty ? "~" : "~\(relative)"
        }
        return pwd
    }
}
