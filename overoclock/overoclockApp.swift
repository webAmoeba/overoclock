import SwiftUI
import AppKit

// MARK: - Notifications
extension Notification.Name {
    static let clockContentChanged = Notification.Name("clockContentChanged")
}

@main
struct FloatingClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: TransparentPanel?
    private var host: NSHostingView<ClockView>?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🕒"
        let menu = NSMenu()
        menu.addItem(withTitle: "Показать/Скрыть часы", action: #selector(toggleWindowVisibility), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выход", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu

        // Create floating, all-spaces panel
        let panel = TransparentPanel(
            contentRect: NSRect(x: 80, y: 80, width: 200, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Content hosting
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

        // Observe size changes to auto-fit window
        NotificationCenter.default.addObserver(self, selector: #selector(resizeToFit), name: .clockContentChanged, object: nil)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        resizeToFit()
    }

    @objc private func toggleWindowVisibility() {
        guard let panel = panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.makeKeyAndOrderFront(nil) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func resizeToFit() {
        guard let panel = panel, let host = host else { return }
        host.layoutSubtreeIfNeeded()
        // Ask SwiftUI for its ideal size
        var size = host.fittingSize
        // Add a tiny padding guard so digits never clip when flipping
        size.width = ceil(size.width + 8)
        size.height = ceil(size.height)
        // Prevent silly tiny sizes
        size.width = max(size.width, 120)
        size.height = max(size.height, 56)
        panel.setContentSize(size)
    }
}

// MARK: - Transparent panel
final class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Clock View
struct ClockView: View {
    @State private var now = Date()

    @AppStorage("showSeconds") private var showSeconds: Bool = false
    @AppStorage("use24h") private var use24h: Bool = true
    @AppStorage("textSize") private var textSize: Double = 18 // fontsize
    @AppStorage("opacity") private var opacity: Double = 0.85
    @AppStorage("clickThrough") private var clickThrough: Bool = false

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = use24h ? (showSeconds ? "HH:mm:ss" : "HH:mm") : (showSeconds ? "h:mm:ss a" : "h:mm a")
        return f
    }

    private var timeText: String { timeFormatter.string(from: now) }

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
            HStack(spacing: 8) {
                Text(timeText)
                    .font(.system(size: textSize, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 0) // padding
                    .padding(.vertical, 10)
            }
        }
        .opacity(opacity)
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
        .contextMenu {
            Toggle("24-часовой формат", isOn: $use24h)
            Toggle("Показывать секунды", isOn: $showSeconds)
            Slider(value: $textSize, in: 18...120) { Text("Размер текста") }
            Slider(value: $opacity, in: 0.3...1.0) { Text("Непрозрачность") }
            Toggle("Клик‑сквозь (не перехватывать клики)", isOn: $clickThrough)
                .onChange(of: clickThrough) { _, newValue in
                    setIgnoresMouseEvents(newValue)
                }
            Divider()
            Button("Закрыть часы") { NSApp.keyWindow?.orderOut(nil) }
        }
        .padding(8)
    }

    private func setIgnoresMouseEvents(_ on: Bool) {
        // Пытаемся найти нашу панель (не всегда keyWindow у неактивной панели)
        if let panel = NSApp.windows.first(where: { $0 is TransparentPanel }) {
            panel.ignoresMouseEvents = on
        } else {
            NSApp.keyWindow?.ignoresMouseEvents = on
        }
    }
}
