import Foundation

enum QuickTerminalTabBarPosition {
    case top
    case left
    case right
    case hidden

    init?(fromGhosttyConfig string: String) {
        switch string {
        case "top":
            self = .top
        case "left":
            self = .left
        case "right":
            self = .right
        case "hidden":
            self = .hidden
        default:
            return nil
        }
    }

    var isVertical: Bool {
        self == .left || self == .right
    }
}
