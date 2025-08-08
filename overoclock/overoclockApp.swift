import SwiftUI
import AppKit

// MARK: - Notifications
extension Notification.Name { static let clockContentChanged = Notification.Name("clockContentChanged") }

@main
struct FloatingClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

// MARK: - App Delegate with menu-bar controls
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: TransparentPanel?
    private var host: NSHostingView<ClockView>?
    private var statusItem: NSStatusItem!

    // Shared keys with SwiftUI @AppStorage
    private let kShowSeconds = "showSeconds"
    private let kUse24h = "use24h"
    private let kTextSize = "textSize"
    private let kOpacity = "opacity"      // background opacity for black pill
    private let kClickThrough = "clickThrough"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock, keep menu-bar presence
        NSApp.setActivationPolicy(.accessory)

        // Menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🕒"
        rebuildMenu()

        // Floating panel across all spaces / full screen
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

        // SwiftUI host
        let host = NSHostingView(rootView: ClockView())
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView?.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            host.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            host.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])

        self.panel = panel
        self.host = host

        // Auto-fit on any content/setting change
        NotificationCenter.default.addObserver(self, selector: #selector(resizeToFit), name: .clockContentChanged, object: nil)

        panel.makeKeyAndOrderFront(nil)
        resizeToFit()
        applyClickThrough()
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

        let fontMenu = NSMenu(title: "Размер шрифта")
        fontMenu.addItem(NSMenuItem(title: "Увеличить (+)", action: #selector(fontIncrease), keyEquivalent: "+"))
        fontMenu.addItem(NSMenuItem(title: "Уменьшить (−)", action: #selector(fontDecrease), keyEquivalent: "-"))
        fontMenu.addItem(NSMenuItem(title: "Сбросить", action: #selector(fontReset), keyEquivalent: "0"))
        let fontParent = NSMenuItem(title: "Размер шрифта", action: nil, keyEquivalent: "")
        menu.setSubmenu(fontMenu, for: fontParent)
        menu.addItem(fontParent)

        let opMenu = NSMenu(title: "Непрозрачность фона")
        opMenu.addItem(NSMenuItem(title: "Больше", action: #selector(opacityIncrease), keyEquivalent: ""))
        opMenu.addItem(NSMenuItem(title: "Меньше", action: #selector(opacityDecrease), keyEquivalent: ""))
        opMenu.addItem(NSMenuItem.separator())
        opMenu.addItem(NSMenuItem(title: "Сбросить", action: #selector(opacityReset), keyEquivalent: ""))
        let opParent = NSMenuItem(title: "Непрозрачность фона", action: nil, keyEquivalent: "")
        menu.setSubmenu(opMenu, for: opParent)
        menu.addItem(opParent)

        let ctItem = NSMenuItem(title: "Клик‑сквозь (не перехватывать клики)", action: #selector(toggleClickThrough), keyEquivalent: "")
        ctItem.state = d.bool(forKey: kClickThrough) ? .on : .off
        menu.addItem(ctItem)

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
        UserDefaults.standard.set(14.0, forKey: kTextSize)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }
    private func adjustFont(by delta: Double) {
        let d = UserDefaults.standard
        let v = min(120.0, max(8.0, d.double(forKey: kTextSize).nonZeroOr(14.0) + delta))
        d.set(v, forKey: kTextSize)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }

    @objc private func opacityIncrease() { adjustOpacity(by: +0.05) }
    @objc private func opacityDecrease() { adjustOpacity(by: -0.05) }
    @objc private func opacityReset() {
        UserDefaults.standard.set(0.85, forKey: kOpacity)
        NotificationCenter.default.post(name: .clockContentChanged, object: nil)
    }
    private func adjustOpacity(by delta: Double) {
        let d = UserDefaults.standard
        let v = min(1.0, max(0.1, d.double(forKey: kOpacity).nonZeroOr(0.85) + delta))
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

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func resizeToFit() {
        guard let panel = panel, let host = host else { return }
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        size.width = ceil(size.width)
        size.height = ceil(size.height)
        size.width = max(size.width, 30)
        size.height = max(size.height, 20)
        panel.setContentSize(size)
    }
}

private extension Double { func nonZeroOr(_ v: Double) -> Double { self == 0 ? v : self } }

// MARK: - Transparent floating panel
final class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - SwiftUI View (black background + white text)
struct ClockView: View {
    @State private var now = Date()
    @AppStorage("showSeconds") private var showSeconds: Bool = false
    @AppStorage("use24h") private var use24h: Bool = true
    @AppStorage("textSize") private var textSize: Double = 14
    @AppStorage("opacity") private var opacity: Double = 1.0   // black background opacity
    @AppStorage("clickThrough") private var clickThrough: Bool = false

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = use24h ? (showSeconds ? "HH:mm:ss" : "HH:mm") : (showSeconds ? "h:mm:ss a" : "h:mm a")
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
        .onChange(of: textSize) { _, _ in NotificationCenter.default.post(name: .clockContentChanged, object: nil) }
        .onChange(of: use24h) { _, _ in NotificationCenter.default.post(name: .clockContentChanged, object: nil) }
        .onChange(of: showSeconds) { _, _ in NotificationCenter.default.post(name: .clockContentChanged, object: nil) }
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

