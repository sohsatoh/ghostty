import Cocoa
import Combine

class QuickTerminalTab: ObservableObject, Identifiable {
    let id = UUID()
    var surfaceTree: SplitTree<Ghostty.SurfaceView>
    @Published var title: String
    @Published var isActive: Bool = false

    private var cancellable: AnyCancellable?

    init(surfaceTree: SplitTree<Ghostty.SurfaceView>, title: String = "Terminal") {
        self.surfaceTree = surfaceTree
        
        // Get the first surface view to extract the title
        if let firstView = surfaceTree.first {
            self.title = firstView.title
            
            // Subscribe to title changes
            self.cancellable = firstView.$title
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newTitle in
                    self?.title = newTitle
                }
        } else {
            self.title = title
        }
    }

    deinit {
        cancellable?.cancel()
    }
}
