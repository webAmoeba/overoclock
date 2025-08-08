//
//  overoclockApp.swift
//  overoclock
//
//  Created by webAmoeba on 8/9/25.
//

//import SwiftUI
//
//@main
//struct overoclockApp: App {
//    var body: some Scene {
//        WindowGroup {
//            ContentView()
//        }
//    }
//}
import SwiftUI
import AppKit

@main
struct FloatingClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView() // no standard settings window
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: TransparentPanel?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar menu for quick quit and options
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🕒"
        let menu = NSMenu()
        menu.addItem(withTitle: "Показать/Скрыть часы", action: #selector(toggleWindowVisibility), keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выход", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu

        // Create panel-style window that can float over full screen spaces
        let panel = TransparentPanel(
            contentRect: NSRect(x: 80, y: 80, width: 180, height: 72),
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
        panel.level = .statusBar // higher than .floating; shows above full-screen apps
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

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

        panel.makeKeyAndOrderFront(nil)
        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleWindowVisibility() {
        guard let window = window else { return }
        if window.isVisible { window.orderOut(nil) } else { window.makeKeyAndOrderFront(nil) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// Transparent, click-through-capable NSPanel
final class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct ClockView: View {
    @State private var now = Date()
    @AppStorage("showSeconds") private var showSeconds: Bool = true
    @AppStorage("use24h") private var use24h: Bool = true
    @AppStorage("textSize") private var textSize: Double = 30
    @AppStorage("opacity") private var opacity: Double = 0.85
    @AppStorage("clickThrough") private var clickThrough: Bool = false
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = use24h ? (showSeconds ? "HH:mm:ss" : "HH:mm") : (showSeconds ? "h:mm:ss a" : "h:mm a")
        return f
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
            HStack(spacing: 8) {
                Text(timeFormatter.string(from: now))
                    .font(.system(size: textSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
            }
        }
        .opacity(opacity)
        .frame(minWidth: 120)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
        .contextMenu {
            Toggle("24-часовой формат", isOn: $use24h)
            Toggle("Показывать секунды", isOn: $showSeconds)
            Slider(value: $textSize, in: 18...96) { Text("Размер текста") }
            Slider(value: $opacity, in: 0.3...1.0) { Text("Непрозрачность") }
            Toggle("Клик‑сквозь (не перехватывать клики)", isOn: $clickThrough)
                .onChange(of: clickThrough) { _, newValue in
                    setIgnoresMouseEvents(newValue)
                }
            Divider()
            Button("Закрепить поверх всего (вкл. по умолчанию)") {}.disabled(true)
            Button("Закрыть часы") {
                NSApp.keyWindow?.orderOut(nil)
            }
        }
        .onAppear { setIgnoresMouseEvents(clickThrough) }
        .padding(8)
    }

    private func setIgnoresMouseEvents(_ on: Bool) {
        if let w = NSApp.keyWindow {
            w.ignoresMouseEvents = on
        }
    }
}
