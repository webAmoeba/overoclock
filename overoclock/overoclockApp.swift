import SwiftUI
import AppKit

// MARK: - Notifications
extension Notification.Name { static let clockContentChanged = Notification.Name("clockContentChanged") }

@main
struct FloatingClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

// MARK: - App Delegate (menu bar + floating panel + position memory)
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var panel: TransparentPanel?
    private var host: NSHostingView<ClockView>?
    private var statusItem: NSStatusItem!

    // Shared keys with SwiftUI @AppStorage
    private let kShowSeconds    = "showSeconds"
    private let kUse24h         = "use24h"
    private let kTextSize       = "textSize"
    private let kOpacity        = "opacity"      // black background opacity
    private let kClickThrough   = "clickThrough"
    // Position persistence
    private let kPosX           = "posX"
    private let kPosY           = "posY"
    private let kUseCustomPos   = "useCustomPos"
    // Pinning
    private let kPinnedTopRight = "pinnedTopRight"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock, keep menu-bar presence
        NSApp.setActivationPolicy(.accessory)

        // Menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🕒"
        rebuildMenu()

        // Floating panel (on top of full-screen spaces)
        let panel = TransparentPanel(
            contentRect: NSRect(x: 80, y: 80, width: 120, height: 30),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.delegate = self

        // SwiftUI host
        let host = NSHostingView(rootView: ClockView())
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        panel.contentView = container
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        self.panel = panel
        self.host = host

        // Observers
        NotificationCenter.default.addObserver(self, selector: #selector(resizeToFit), name: .clockContentChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParamsChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        panel.makeKeyAndOrderFront(nil)
        resizeToFit()
        // Launch behavior: if pinned, force top-right; else restore or snap.
        let d = UserDefaults.standard
        if d.object(forKey: kPinnedTopRight) == nil { d.set(true, forKey: kPinnedTopRight) } // default ON
        if d.bool(forKey: kPinnedTopRight) {
            resetPositionTopRight()
        } else if !restorePositionIfAvailable() {
            snapTopRightReliably()
        }
        applyClickThrough()
        updateDraggability()
    }

    // MARK: - Positioning
    private func targetScreen() -> NSScreen? {
        if let s = panel?.screen { return s }
        let mouse = NSEvent.mouseLocation
        if let byMouse = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return byMouse }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func snapTopRightReliably() {
        // Do a few passes to outlive any async layout/space switches
        _ = positionTopRight()
        DispatchQueue.main.async { _ = self.positionTopRight() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { _ = self.positionTopRight() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _ = self.positionTopRight() }
    }

    @discardableResult
    private func positionTopRight(marginX: CGFloat = 0, marginY: CGFloat = 0) -> Bool {
        guard let panel = panel, let f = targetScreen()?.frame else { return false }
        let size = panel.frame.size
        let x = f.maxX - size.width - marginX
        let y = f.maxY - size.height - marginY
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        return true
    }

    @objc private func screenParamsChanged() {
        resizeToFit()
        let d = UserDefaults.standard
        if d.bool(forKey: kPinnedTopRight) {
            resetPositionTopRight() // pins again
        } else if d.bool(forKey: kUseCustomPos) {
            if !restorePositionIfAvailable() { snapTopRightReliably() }
        } else {
            snapTopRightReliably()
        }
    }

    // MARK: - Menu
    private func rebuildMenu() {
        let d = UserDefaults.standard
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: "Показать/Скрыть часы", action: #selector(toggleWindowVisibility), keyEquivalent: "s")
        menu.addItem(.separator())

        let use24Item = NSMenuItem(title: "24-часовой формат", action: #selector(toggleUse24h), keyEquivalent: "")
        use24Item.state = d.bool(forKey: kUse24h) ? .on : .off
        menu.addItem(use24Item)

        let secItem = NSMenuItem(title: "Показывать секунды", action: #selector(toggleSeconds), keyEquivalent: "")
        secItem.state = d.bool(forKey: kShowSeconds) ? .on : .off
        menu.addItem(secItem)

        // Font size submenu
        let fontMenu = NSMenu(title: "Размер шрифта")
        fontMenu.addItem(NSMenuItem(title: "Увеличить (+)", action: #selector(fontIncrease), keyEquivalent: "+"))
        fontMenu.addItem(NSMenuItem(title: "Уменьшить (−)", action: #selector(fontDecrease), keyEquivalent: "-"))
        fontMenu.addItem(NSMenuItem(title: "Сбросить", action: #selector(fontReset), keyEquivalent: "0"))
        let fontParent = NSMenuItem(title: "Размер шрифта", action: nil, keyEquivalent: "")
        menu.setSubmenu(fontMenu, for: fontParent)
        menu.addItem(fontParent)

        // Opacity submenu
        let opMenu = NSMenu(title: "Непрозрачность фона")
        opMenu.addItem(NSMenuItem(title: "Больше", action: #selector(opacityIncrease), keyEquivalent: ""))
        opMenu.addItem(NSMenuItem(title: "Меньше", action: #selector(opacityDecrease), keyEquivalent: ""))
        opMenu.addItem(NSMenuItem.separator())
        opMenu.addItem(NSMenuItem(title: "Сбросить", action: #selector(opacityReset), keyEquivalent: ""))
        let opParent = NSMenuItem(title: "Непрозрачность фона", action: nil, keyEquivalent: "")
        menu.setSubmenu(opMenu, for: opParent)
        menu.addItem(opParent)

        // Click-through toggle
        let ctItem = NSMenuItem(title: "Клик‑сквозь (не перехватывать клики)", action: #selector(toggleClickThrough), keyEquivalent: "")
        ctItem.state = d.bool(forKey: kClickThrough) ? .on : .off
        menu.addItem(ctItem)

        // Pinning
        let pinItem = NSMenuItem(title: "Прибить к правому верхнему (авто)", action: #selector(togglePinned), keyEquivalent: "")
        pinItem.state = d.bool(forKey: kPinnedTopRight) ? .on : .off
        menu.addItem(pinItem)

        // Position controls
        menu.addItem(.separator())
        menu.addItem(withTitle: "Сбросить положение (правый верх)", action: #selector(resetPositionTopRight), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Выход", action: #selector(quit), keyEquivalent: "q")

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    // MARK: - Actions
    @objc private func toggleWindowVisibility() {
        guard let panel = panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.makeKeyAndOrderFront(nil) }
    }
    @objc private func toggleUse24h() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: kUse24h), forKey: kUse24h)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }
    @objc private func toggleSeconds() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: kShowSeconds), forKey: kShowSeconds)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }

    @objc private func fontIncrease() { adjustFont(by: +2) }
    @objc private func fontDecrease() { adjustFont(by: -2) }
    @objc private func fontReset() {
        UserDefaults.standard.set(16.0, forKey: kTextSize)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }
    private func adjustFont(by delta: Double) {
        let d = UserDefaults.standard
        let v = min(120.0, max(8.0, d.double(forKey: kTextSize).nonZeroOr(16.0) + delta))
        d.set(v, forKey: kTextSize)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }

    @objc private func opacityIncrease() { adjustOpacity(by: +0.05) }
    @objc private func opacityDecrease() { adjustOpacity(by: -0.05) }
    @objc private func opacityReset() {
        UserDefaults.standard.set(1.0, forKey: kOpacity)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }
    private func adjustOpacity(by delta: Double) {
        let d = UserDefaults.standard
        let v = min(1.0, max(0.1, d.double(forKey: kOpacity).nonZeroOr(1.0) + delta))
        d.set(v, forKey: kOpacity)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }

    @objc private func toggleClickThrough() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: kClickThrough), forKey: kClickThrough)
        applyClickThrough()
    }
    private func applyClickThrough() {
        guard let panel = panel else { return }
        panel.ignoresMouseEvents = UserDefaults.standard.bool(forKey: kClickThrough)
    }

    @objc private func togglePinned() {
        let d = UserDefaults.standard
        let newVal = !d.bool(forKey: kPinnedTopRight)
        d.set(newVal, forKey: kPinnedTopRight)
        updateDraggability()
        if newVal {
            // When enabling pin, drop custom pos and snap
            d.set(false, forKey: kUseCustomPos)
            resetPositionTopRight()
        }
    }

    private func updateDraggability() {
        let pinned = UserDefaults.standard.bool(forKey: kPinnedTopRight)
        panel?.isMovableByWindowBackground = !pinned
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func resizeToFit() {
        guard let panel = panel, let host = host else { return }
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        size.width = ceil(size.width)
        size.height = ceil(size.height)
        size.width = max(size.width, 30)
        size.height = max(size.height, 20)
        let d = UserDefaults.standard
        let pinned = d.bool(forKey: kPinnedTopRight)
        let hadCustom = d.bool(forKey: kUseCustomPos)
        let oldOrigin = panel.frame.origin
        panel.setContentSize(size)
        if pinned {
            snapTopRightReliably()
        } else if hadCustom {
            panel.setFrameOrigin(NSPoint(x: oldOrigin.x, y: oldOrigin.y))
        } else {
            snapTopRightReliably()
        }
    }

    // MARK: - Position persistence
    private func savePosition() {
        guard let panel = panel else { return }
        if UserDefaults.standard.bool(forKey: kPinnedTopRight) { return } // don't save when pinned
        let o = panel.frame.origin
        let d = UserDefaults.standard
        d.set(Double(o.x), forKey: kPosX)
        d.set(Double(o.y), forKey: kPosY)
        d.set(true, forKey: kUseCustomPos)
    }

    @discardableResult
    private func restorePositionIfAvailable() -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: kUseCustomPos) else { return false }
        guard let x = d.object(forKey: kPosX) as? Double,
              let y = d.object(forKey: kPosY) as? Double else { return false }
        if x < 5 && y < 5 { return false }
        let pt = NSPoint(x: x, y: y)
        if isPointOnAnyScreen(pt) { panel?.setFrameOrigin(pt); return true }
        return false
    }

    private func isPointOnAnyScreen(_ p: NSPoint) -> Bool {
        for s in NSScreen.screens { if s.frame.contains(p) { return true } }
        return false
    }

    @objc private func resetPositionTopRight() {
        let d = UserDefaults.standard
        d.removeObject(forKey: kPosX)
        d.removeObject(forKey: kPosY)
        d.set(false, forKey: kUseCustomPos)
        snapTopRightReliably()
    }

    // NSWindowDelegate — persist position when user drags
    func windowDidMove(_ notification: Notification) { savePosition() }
}

// MARK: - Helpers
private extension Double { func nonZeroOr(_ v: Double) -> Double { self == 0 ? v : self } }

final class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - SwiftUI view (black pill, white mono text)
struct ClockView: View {
    @State private var now = Date()
    @AppStorage("showSeconds") private var showSeconds: Bool = false
    @AppStorage("use24h")     private var use24h: Bool = true
    @AppStorage("textSize")   private var textSize: Double = 16
    @AppStorage("opacity")    private var opacity: Double = 1.0   // default: fully black
    @AppStorage("clickThrough") private var clickThrough: Bool = false

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = use24h ? (showSeconds ? "HH:mm:ss" : "HH:mm")
                              : (showSeconds ? "h:mm:ss a" : "h:mm a")
        return f
    }
    private var timeText: String { timeFormatter.string(from: now) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(opacity))
            Text(timeText)
                .font(.system(size: textSize, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
            NotificationCenter.default.post(name: .clockContentChanged, object: nil)
        }
        .onChange(of: textSize)   { _, _ in NotificationCenter.default.post(name: .clockContentChanged, object: nil) }
        .onChange(of: use24h)     { _, _ in NotificationCenter.default.post(name: .clockContentChanged, object: nil) }
        .onChange(of: showSeconds){ _, _ in NotificationCenter.default.post(name: .clockContentChanged, object: nil) }
        .onAppear {
            setIgnoresMouseEvents(clickThrough)
            NotificationCenter.default.post(name: .clockContentChanged, object: nil)
        }
    }

    private func setIgnoresMouseEvents(_ on: Bool) {
        if let panel = NSApp.windows.first(where: { $0 is TransparentPanel }) {
            panel.ignoresMouseEvents = on
        }
    }
}
