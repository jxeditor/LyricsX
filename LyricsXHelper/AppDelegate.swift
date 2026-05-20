//
//  AppDelegate.swift
//  LyricsXHelper
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createStatusItem()
        writeDiagnostics(reason: "launch")
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = ""
        statusItem.button?.image = statusIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "LyricsX"
        statusItem.menu = makeMenu()
    }

    private func statusIcon() -> NSImage? {
        var host = Bundle.main.bundleURL
        for _ in 0..<4 {
            host.deleteLastPathComponent()
        }
        let image = Bundle(url: host)?.image(forResource: "status_bar_icon")
            ?? NSImage(named: NSImage.Name("NSApplicationIcon"))
        image?.isTemplate = true
        return image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "LyricsX")
        menu.addItem(item("显示歌词窗口", action: #selector(showLyricsWindow)))
        menu.addItem(item("搜索歌词...", action: #selector(searchLyrics)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("切换菜单栏歌词", action: #selector(toggleMenuBarLyrics)))
        menu.addItem(item("切换桌面歌词", action: #selector(toggleDesktopLyrics)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("偏好设置...", action: #selector(showPreferences)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("退出 LyricsX", action: #selector(quitLyricsX)))
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showLyricsWindow() {
        openMain(action: "show-lyrics-window")
    }

    @objc private func searchLyrics() {
        openMain(action: "search")
    }

    @objc private func toggleMenuBarLyrics() {
        openMain(action: "toggle-menu-bar-lyrics")
    }

    @objc private func toggleDesktopLyrics() {
        openMain(action: "toggle-desktop-lyrics")
    }

    @objc private func showPreferences() {
        openMain(action: "preferences")
    }

    @objc private func quitLyricsX() {
        openMain(action: "quit")
        NSApp.terminate(nil)
    }

    private func openMain(action: String? = nil) {
        if let action = action, let url = URL(string: "lyricsx://\(action)") {
            NSWorkspace.shared.open(url)
            return
        }

        var host = Bundle.main.bundleURL
        for _ in 0..<4 {
            host.deleteLastPathComponent()
        }
        try? NSWorkspace.shared.launchApplication(at: host, configuration: [:])
    }

    private func writeDiagnostics(reason: String) {
        let button = statusItem.button
        let window = button?.window
        let frame = button.map { window?.convertToScreen($0.frame) ?? .zero } ?? .zero
        let lines = [
            "reason=\(reason)",
            "pid=\(getpid())",
            "buttonFrame=\(button?.frame.debugDescription ?? "nil")",
            "screenFrame=\(frame.debugDescription)",
            "title=\(button?.title ?? "nil")",
            "hasImage=\(button?.image != nil)",
            "menuAttached=\(statusItem.menu != nil)"
        ]
        try? (lines.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: "/tmp/lyricsx-helper-statusitem-check.log"),
                                                          atomically: true,
                                                          encoding: .utf8)
    }
}
