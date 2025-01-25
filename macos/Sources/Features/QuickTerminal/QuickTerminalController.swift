import Foundation
import Cocoa
import SwiftUI
import GhosttyKit

// This is a Apple's private function that we need to call to get the active space.
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: Int) -> size_t
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

/// Controller for the "quick" terminal.
class QuickTerminalController: BaseTerminalController {
    override var windowNibName: NSNib.Name? { "QuickTerminal" }

    /// The position for the quick terminal.
    let position: QuickTerminalPosition

    /// The current state of the quick terminal
    private(set) var visible: Bool = false

    /// The previously running application when the terminal is shown. This is NEVER Ghostty.
    /// If this is set then when the quick terminal is animated out then we will restore this
    /// application to the front.
    private var previousApp: NSRunningApplication? = nil

    // The active space when the quick terminal was last shown.
    private var previousActiveSpace: size_t = 0

    /// Non-nil if we have hidden dock state.
    private var hiddenDock: HiddenDock? = nil

    /// The configuration derived from the Ghostty config so we don't need to rely on references.
    private var derivedConfig: DerivedConfig

    // The tab manager for the quick terminal
    private lazy var tabManager: QuickTerminalTabManager = {
        let manager = QuickTerminalTabManager(controller: self)
        return manager
    }()

    init(
        _ ghostty: Ghostty.App,
        position: QuickTerminalPosition = .top,
        baseConfig base: Ghostty.SurfaceConfiguration? = nil,
        surfaceTree tree: Ghostty.SplitNode? = nil
    ) {
        self.position = position
        self.derivedConfig = DerivedConfig(ghostty.config)
        super.init(ghostty, baseConfig: base, surfaceTree: tree)

        // Setup our notifications for behaviors
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onToggleFullscreen),
            name: Ghostty.Notification.ghosttyToggleFullscreen,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onNewTab(_:)),
            name: Ghostty.Notification.ghosttyNewTab,
            object: nil)
        center.addObserver(
            tabManager,
            selector: #selector(tabManager.onMoveTab(_:)),
            name: .ghosttyMoveTab,
            object: nil)
        center.addObserver(
            tabManager,
            selector: #selector(tabManager.onGoToTab(_:)),
            name: Ghostty.Notification.ghosttyGotoTab,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    deinit {
        // Remove all of our notificationcenter subscriptions
        let center = NotificationCenter.default
        center.removeObserver(self)

        // Make sure we restore our hidden dock
        hiddenDock = nil
    }

    // MARK: NSWindowController

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window = self.window else { return }

        // The controller is the window delegate so we can detect events such as
        // window close so we can animate out.
        window.delegate = self

        // The quick window is not restorable (yet!). "Yet" because in theory we can
        // make this restorable, but it isn't currently implemented.
        window.isRestorable = false

        // Setup our configured appearance that we support.
        syncAppearance()

        // Setup our initial size based on our configured position
        position.setLoaded(window)

        DispatchQueue.main.async {
            self.setupMainView()
            self.animateIn()
        }
    }

    private func setupMainView() {
        guard let window = self.window else { return }

        let leaf: Ghostty.SplitNode.Leaf = .init(ghostty.app!, baseConfig: nil)
        let surface: Ghostty.SplitNode = .leaf(leaf)
        let initialTab = QuickTerminalTab(surface: surface)
        initialTab.isActive = true
        tabManager.tabs.append(initialTab)
        tabManager.currentTab = initialTab
        surfaceTree = surface
        focusedSurface = leaf.surface

        let mainContent = VStack(spacing: 0) {
            QuickTerminalTabBarView(tabManager: tabManager)
            TerminalView(
                ghostty: ghostty,
                viewModel: self,
                delegate: self
            )
        }

        window.contentView = NSHostingView(rootView: mainContent)
    }

    // MARK: NSWindowDelegate

    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)

        // If we're not visible we don't care to run the logic below. It only
        // applies if we can be seen.
        guard visible else { return }

        // Re-hide the dock if we were hiding it before.
        hiddenDock?.hide()
    }

    override func windowDidResignKey(_ notification: Notification) {
        super.windowDidResignKey(notification)

        // If we're not visible then we don't want to run any of the logic below
        // because things like resetting our previous app assume we're visible.
        // windowDidResignKey will also get called after animateOut so this
        // ensures we don't run logic twice.
        guard visible else { return }

        // We don't animate out if there is a modal sheet being shown currently.
        // This lets us show alerts without causing the window to disappear.
        guard window?.attachedSheet == nil else { return }

        // If our app is still active, then it means that we're switching
        // to another window within our app, so we remove the previous app
        // so we don't restore it.
        if NSApp.isActive {
            self.previousApp = nil
        }

        // Regardless of autohide, we always want to bring the dock back
        // when we lose focus.
        hiddenDock?.restore()

        if derivedConfig.quickTerminalAutoHide {
            switch derivedConfig.quickTerminalSpaceBehavior {
            case .remain:
                // If we lose focus on the active space, then we can animate out
                animateOut()

            case .move:
                let currentActiveSpace = CGSGetActiveSpace(CGSMainConnectionID())
                if previousActiveSpace == currentActiveSpace {
                    // We haven't moved spaces. We lost focus to another app on the
                    // current space. Animate out.
                    animateOut()
                } else {
                    // We've moved to a different space. Bring the quick terminal back
                    // into view.
                    DispatchQueue.main.async {
                        self.window?.makeKeyAndOrderFront(nil)
                    }

                    self.previousActiveSpace = currentActiveSpace
                }
            }
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // We use the actual screen the window is on for this, since it should
        // be on the proper screen.
        guard let screen = window?.screen ?? NSScreen.main else { return frameSize }
        return position.restrictFrameSize(frameSize, on: screen)
    }

    // MARK: Base Controller Overrides

    override func surfaceTreeDidChange(from: Ghostty.SplitNode?, to: Ghostty.SplitNode?) {
        super.surfaceTreeDidChange(from: from, to: to)

        // If we have a tab with surfaces removed from surfaceTree, we need to remove them from the tab manager by calling closeTab
        if to == nil {
            tabManager.tabs
                .filter { tab in
                    tab.surface.contains { $0.surface.surface == nil }
                }
                .forEach { tab in
                    tabManager.closeTab(tab)
                }
        }
    }

    // MARK: Methods

    func toggle() {
        if visible {
            animateOut()
        } else {
            animateIn()
        }
    }

    func animateIn() {
        guard let window = self.window else { return }

        // Set our visibility state
        guard !visible else { return }
        visible = true

        // Notify the change
        NotificationCenter.default.post(
            name: .quickTerminalDidChangeVisibility,
            object: self
        )

        // If we have a previously focused application and it isn't us, then
        // we want to store it so we can restore state later.
        if !NSApp.isActive {
            if let previousApp = NSWorkspace.shared.frontmostApplication,
                previousApp.bundleIdentifier != Bundle.main.bundleIdentifier
            {
                self.previousApp = previousApp
            }
        }

        // Set previous active space
        self.previousActiveSpace = CGSGetActiveSpace(CGSMainConnectionID())

        // Animate the window in
        animateWindowIn(window: window, from: position)

        // If our surface tree is nil then we initialize a new terminal. The surface
        // tree can be nil if for example we run "eixt" in the terminal and force
        // animate out.
        if surfaceTree == nil {
            let leaf: Ghostty.SplitNode.Leaf = .init(ghostty.app!, baseConfig: nil)
            surfaceTree = .leaf(leaf)
            focusedSurface = leaf.surface
        }
    }

    func animateOut() {
        guard let window = self.window else { return }

        // Set our visibility state
        guard visible else { return }
        visible = false

        // Notify the change
        NotificationCenter.default.post(
            name: .quickTerminalDidChangeVisibility,
            object: self
        )

        animateWindowOut(window: window, to: position)
    }

    private func animateWindowIn(window: NSWindow, from position: QuickTerminalPosition) {
        guard let screen = derivedConfig.quickTerminalScreen.screen else { return }

        // Move our window off screen to the top
        position.setInitial(in: window, on: screen)

        // We need to set our window level to a high value. In testing, only
        // popUpMenu and above do what we want. This gets it above the menu bar
        // and lets us render off screen.
        window.level = .popUpMenu

        // Move it to the visible position since animation requires this
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }

        // If our dock position would conflict with our target location then
        // we autohide the dock.
        if position.conflictsWithDock(on: screen) {
            if (hiddenDock == nil) {
                hiddenDock = .init()
            }

            hiddenDock?.hide()
        } else {
            // Ensure we don't have any hidden dock if we don't conflict.
            // The deinit will restore.
            hiddenDock = nil
        }

        // Run the animation that moves our window into the proper place and makes
        // it visible.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = derivedConfig.quickTerminalAnimationDuration
            context.timingFunction = .init(name: .easeIn)
            position.setFinal(in: window.animator(), on: screen)
        }, completionHandler: {
            // There is a very minor delay here so waiting at least an event loop tick
            // keeps us safe from the view not being on the window.
            DispatchQueue.main.async {
                // If we canceled our animation clean up some state.
                guard self.visible else {
                    self.hiddenDock = nil
                    return
                }

                // After animating in, we reset the window level to a value that
                // is above other windows but not as high as popUpMenu. This allows
                // things like IME dropdowns to appear properly.
                window.level = .floating

                    // Now that the window is visible, sync our appearance. This function
                    // requires the window is visible.
                    self.syncAppearance()

                    // Once our animation is done, we must grab focus since we can't grab
                    // focus of a non-visible window.
                    self.makeWindowKey(window)

                    // If our application is not active, then we grab focus. Its important
                    // we do this AFTER our window is animated in and focused because
                    // otherwise macOS will bring forward another window.
                    if !NSApp.isActive {
                        NSApp.activate(ignoringOtherApps: true)

                        // This works around a really funky bug where if the terminal is
                        // shown on a screen that has no other Ghostty windows, it takes
                        // a few (variable) event loop ticks until we can actually focus it.
                        // https://github.com/ghostty-org/ghostty/issues/2409
                        //
                        // We wait one event loop tick to try it because under the happy
                        // path (we have windows on this screen) it takes one event loop
                        // tick for window.isKeyWindow to return true.
                        DispatchQueue.main.async {
                            guard !window.isKeyWindow else { return }
                            self.makeWindowKey(window, retries: 10)
                        }
                    }
                }
            })
    }

    /// Attempt to make a window key, supporting retries if necessary. The retries will be attempted
    /// on a separate event loop tick.
    ///
    /// The window must contain the focused surface for this terminal controller.
    private func makeWindowKey(_ window: NSWindow, retries: UInt8 = 0) {
        // We must be visible
        guard visible else { return }

        // If our focused view is somehow not connected to this window then the
        // function calls below do nothing. I don't think this is possible but
        // we should guard against it because it is a Cocoa assertion.
        guard let focusedSurface, focusedSurface.window == window else { return }

        // The window must become top-level
        window.makeKeyAndOrderFront(nil)

        // The view must gain our keyboard focus
        window.makeFirstResponder(focusedSurface)

        // If our window is already key then we're done!
        guard !window.isKeyWindow else { return }

        // If we don't have retries then we're done
        guard retries > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) {
            self.makeWindowKey(window, retries: retries - 1)
        }
    }

    private func animateWindowOut(window: NSWindow, to position: QuickTerminalPosition) {
        // If we hid the dock then we unhide it.
        hiddenDock = nil

        // If the window isn't on our active space then we don't animate, we just
        // hide it.
        if !window.isOnActiveSpace {
            self.previousApp = nil
            window.orderOut(self)
            return
        }

        // We always animate out to whatever screen the window is actually on.
        guard let screen = window.screen ?? NSScreen.main else { return }

        // If we are in fullscreen, then we exit fullscreen.
        if let fullscreenStyle, fullscreenStyle.isFullscreen {
            fullscreenStyle.exit()
        }

        // If we have a previously active application, restore focus to it. We
        // do this BEFORE the animation below because when the animation completes
        // macOS will bring forward another window.
        if let previousApp = self.previousApp {
            // Make sure we unset the state no matter what
            self.previousApp = nil

            if !previousApp.isTerminated {
                // Ignore the result, it doesn't change our behavior.
                _ = previousApp.activate(options: [])
            }
        }

        // We need to set our window level to a high value. In testing, only
        // popUpMenu and above do what we want. This gets it above the menu bar
        // and lets us render off screen.
        window.level = .popUpMenu

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = derivedConfig.quickTerminalAnimationDuration
            context.timingFunction = .init(name: .easeIn)
            position.setInitial(in: window.animator(), on: screen)
        }, completionHandler: {
            // This causes the window to be removed from the screen list and macOS
            // handles what should be focused next.
            window.orderOut(self)
        })
    }

    private func syncAppearance() {
        guard let window else { return }

        // Change the collection behavior of the window depending on the configuration.
        window.collectionBehavior = derivedConfig.quickTerminalSpaceBehavior.collectionBehavior

        // If our window is not visible, then no need to sync the appearance yet.
        // Some APIs such as window blur have no effect unless the window is visible.
        guard window.isVisible else { return }

        // If we have window transparency then set it transparent. Otherwise set it opaque.
        if self.derivedConfig.backgroundOpacity < 1 {
            window.isOpaque = false

            // This is weird, but we don't use ".clear" because this creates a look that
            // matches Terminal.app much more closer. This lets users transition from
            // Terminal.app more easily.
            window.backgroundColor = .white.withAlphaComponent(0.001)

            ghostty_set_window_background_blur(ghostty.app, Unmanaged.passUnretained(window).toOpaque())
        } else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        }
    }

    func updateSurfaceTree(to newTree: Ghostty.SplitNode) {
        self.surfaceTree = newTree
        if case let .leaf(leaf) = newTree {
            self.focusedSurface = leaf.surface
            guard let window = self.window, self.focusedSurface?.window == window else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) {
                    self.updateSurfaceTree(to: newTree)
                }
                return
            }
            makeWindowKey(window, retries: 10)
        }
    }

    // MARK: First Responder
    @IBAction func toggleGhosttyFullScreen(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.toggleFullscreen(surface: surface)
    }

    // MARK: Notifications

    @objc private func applicationWillTerminate(_ notification: Notification) {
        // If the application is going to terminate we want to make sure we
        // restore any global dock state. I think deinit should be called which
        // would call this anyways but I can't be sure so I will do this too.
        hiddenDock = nil
    }

    @objc private func onToggleFullscreen(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // We ignore the requested mode and always use non-native for the quick terminal
        toggleFullscreen(mode: .nonNative)
    }

    @objc private func ghosttyConfigDidChange(_ notification: Notification) {
        // We only care if the configuration is a global configuration, not a
        // surface-specific one.
        guard notification.object == nil else { return }

        // Get our managed configuration object out
        guard
            let config = notification.userInfo?[
                Notification.Name.GhosttyConfigChangeKey
            ] as? Ghostty.Config
        else { return }

        // Update our derived config
        self.derivedConfig = DerivedConfig(config)

        syncAppearance()
    }

    @objc func onNewTab(_ sender: Any?) {
        tabManager.newTab()
    }

    private struct DerivedConfig {
        let quickTerminalScreen: QuickTerminalScreen
        let quickTerminalAnimationDuration: Double
        let quickTerminalAutoHide: Bool
        let quickTerminalSpaceBehavior: QuickTerminalSpaceBehavior
        let backgroundOpacity: Double

        init() {
            self.quickTerminalScreen = .main
            self.quickTerminalAnimationDuration = 0.2
            self.quickTerminalAutoHide = true
            self.quickTerminalSpaceBehavior = .move
            self.backgroundOpacity = 1.0
        }

        init(_ config: Ghostty.Config) {
            self.quickTerminalScreen = config.quickTerminalScreen
            self.quickTerminalAnimationDuration = config.quickTerminalAnimationDuration
            self.quickTerminalAutoHide = config.quickTerminalAutoHide
            self.quickTerminalSpaceBehavior = config.quickTerminalSpaceBehavior
            self.backgroundOpacity = config.backgroundOpacity
        }
    }

    /// Hides the dock globally (not just NSApp). This is only used if the quick terminal is
    /// in a conflicting position with the dock.
    private class HiddenDock {
        let previousAutoHide: Bool
        private var hidden: Bool = false

        init() {
            previousAutoHide = Dock.autoHideEnabled
        }

        deinit {
            restore()
        }

        func hide() {
            guard !hidden else { return }
            NSApp.acquirePresentationOption(.autoHideDock)
            Dock.autoHideEnabled = true
            hidden = true
        }

        func restore() {
            guard hidden else { return }
            NSApp.releasePresentationOption(.autoHideDock)
            Dock.autoHideEnabled = previousAutoHide
            hidden = false
        }
    }
}

extension Notification.Name {
    /// The quick terminal did become hidden or visible.
    static let quickTerminalDidChangeVisibility = Notification.Name("QuickTerminalDidChangeVisibility")
}
