//
//  MenuBarLyrics.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Cocoa
import CXExtensions
import CXShim
import GenericID
import LyricsCore
import MusicPlayer
import OpenCC
import SwiftCF
import AccessibilityExt

class MenuBarLyricsController {
    
    static let shared = MenuBarLyricsController()
    
    private(set) var statusItem: NSStatusItem!
    var lyricsItem: NSStatusItem?
    var buttonImage = #imageLiteral(resourceName: "status_bar_icon")
    
    private var screenLyrics = "" {
        didSet {
            DispatchQueue.main.async {
                self.updateStatusItem()
            }
        }
    }
    
    private var cancelBag = Set<AnyCancellable>()
    
    private init() {
        statusItem = makeStatusItem()
        AppController.shared.$currentLyrics
            .combineLatest(AppController.shared.$currentLineIndex)
            .receive(on: DispatchQueue.lyricsDisplay.cx)
            .invoke(MenuBarLyricsController.handleLyricsDisplay, weaklyOn: self)
            .store(in: &cancelBag)
        workspaceNC.cx
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .signal()
            .invoke(MenuBarLyricsController.updateStatusItem, weaklyOn: self)
            .store(in: &cancelBag)
        defaults.publisher(for: [.menuBarLyricsEnabled, .combinedMenubarLyrics])
            .prepend()
            .invoke(MenuBarLyricsController.updateStatusItem, weaklyOn: self)
            .store(in: &cancelBag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.writeStatusItemDiagnostics(reason: "launch")
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        Self.prepareStatusItemPreferences()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "LyricsX"
        item.isVisible = true
        return item
    }

    private static func prepareStatusItemPreferences() {
        let controlCenterDefaults = UserDefaults(suiteName: "com.apple.controlcenter")
        controlCenterDefaults?.set(true, forKey: "NSStatusItem Visible LyricsX")
        controlCenterDefaults?.set(false, forKey: "NSStatusItem VisibleCC LyricsX")
        controlCenterDefaults?.set(120, forKey: "NSStatusItem Preferred Position LyricsX")
        controlCenterDefaults?.synchronize()
    }
    
    private func handleLyricsDisplay(event: (lyrics: Lyrics?, index: Int?)) {
        guard !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying,
            let lyrics = event.lyrics,
            let index = event.index else {
            screenLyrics = ""
            return
        }
        var newScreenLyrics = lyrics.lines[index].content
        if let converter = ChineseConverter.shared, lyrics.metadata.language?.hasPrefix("zh") == true {
            newScreenLyrics = converter.convert(newScreenLyrics)
        }
        if newScreenLyrics == screenLyrics {
            return
        }
        screenLyrics = newScreenLyrics
    }
    
    @objc private func updateStatusItem() {
        guard defaults[.menuBarLyricsEnabled], !screenLyrics.isEmpty else {
            setImageStatusItem()
            removeLyricsItem()
            return
        }
        
        if defaults[.combinedMenubarLyrics] {
            updateCombinedStatusLyrics()
        } else {
            updateSeparateStatusLyrics()
        }
    }
    
    private func updateSeparateStatusLyrics() {
        setImageStatusItem()
        
        if lyricsItem == nil {
            lyricsItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        lyricsItem?.button?.title = screenLyrics
    }
    
    private func updateCombinedStatusLyrics() {
        removeLyricsItem()
        
        setTextStatusItem(string: screenLyrics)
        if statusItem.isVisibe {
            return
        }
        
        // truncation
        var components = screenLyrics.components(options: [.byWords])
        while !components.isEmpty, !statusItem.isVisibe {
            components.removeLast()
            let proposed = components.joined() + "..."
            setTextStatusItem(string: proposed)
        }
    }
    
    private func setTextStatusItem(string: String) {
        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
        statusItem.button?.title = string
        statusItem.button?.image = nil
    }
    
    private func setImageStatusItem() {
        statusItem.length = NSStatusItem.variableLength
        statusItem.isVisible = true
        guard let button = statusItem.button else {
            writeStatusItemDiagnostics(reason: "missing-button")
            return
        }
        button.subviews.forEach { $0.removeFromSuperview() }
        button.title = "LyricsX"
        button.image = nil
        button.toolTip = "LyricsX"
        button.imagePosition = .noImage
        button.isEnabled = true
        button.isHidden = false
        button.alphaValue = 1
    }
    
    private func removeLyricsItem() {
        if let lyricsItem = lyricsItem {
            NSStatusBar.system.removeStatusItem(lyricsItem)
            self.lyricsItem = nil
        }
    }

    func writeStatusItemDiagnostics(reason: String) {
        let button = statusItem.button
        let window = button?.window
        let frame = button.map { window?.convertToScreen($0.frame) ?? .zero } ?? .zero
        let axHit = accessibilityHitDescription(at: frame.center)
        let lines = [
            "reason=\(reason)",
            "pid=\(getpid())",
            "isVisible=\(statusItem.isVisible)",
            "length=\(statusItem.length)",
            "hasButton=\(button != nil)",
            "hasWindow=\(window != nil)",
            "windowNumber=\(window?.windowNumber ?? 0)",
            "windowLevel=\(window?.level.rawValue ?? 0)",
            "windowClass=\(window.map { String(describing: type(of: $0)) } ?? "nil")",
            "autosaveName=\(statusItem.autosaveName)",
            "buttonFrame=\(button?.frame.debugDescription ?? "nil")",
            "screenFrame=\(frame.debugDescription)",
            "axHit=\(axHit)",
            "title=\(button?.title ?? "nil")",
            "hasImage=\(button?.image != nil)",
            "subviews=\(button?.subviews.map { String(describing: type(of: $0)) }.joined(separator: ",") ?? "nil")",
            "screens=\(NSScreen.screens.enumerated().map { idx, screen in "#\(idx) frame=\(screen.frame.debugDescription) visible=\(screen.visibleFrame.debugDescription)" }.joined(separator: " | "))",
            "menuAttached=\(statusItem.menu != nil)",
            "menuBarLyricsEnabled=\(defaults[.menuBarLyricsEnabled])",
            "combinedMenubarLyrics=\(defaults[.combinedMenubarLyrics])"
        ]
        let output = lines.joined(separator: "\n") + "\n"
        try? output.write(to: URL(fileURLWithPath: "/tmp/lyricsx-statusitem-check.log"), atomically: true, encoding: .utf8)
        log(output)
    }

    func refreshStatusItemForDiagnostics(reason: String) {
        updateStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.writeStatusItemDiagnostics(reason: reason)
        }
    }

    private func accessibilityHitDescription(at point: CGPoint) -> String {
        guard point != .zero else {
            return "nil"
        }
        let topLeftPoint = topLeftAccessibilityPoint(from: point)
        guard let element = try? AXUIElement.systemWide().element(at: topLeftPoint) else {
            return "nil"
        }
        let pid = (try? element.pid()) ?? 0
        return "pid:\(pid)"
    }

    private func accessibilityHitPID(at point: CGPoint) -> pid_t {
        guard point != .zero else {
            return 0
        }
        let topLeftPoint = topLeftAccessibilityPoint(from: point)
        guard let element = try? AXUIElement.systemWide().element(at: topLeftPoint),
              let pid = try? element.pid() else {
            return 0
        }
        return pid
    }

    private func topLeftAccessibilityPoint(from point: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return point
        }
        return CGPoint(x: point.x, y: screen.frame.height - point.y - 1)
    }

}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

// MARK: - Status Item Visibility

private extension NSStatusItem {
    
    var isVisibe: Bool {
        guard let buttonFrame = button?.frame,
            let frame = button?.window?.convertToScreen(buttonFrame) else {
                return false
        }
        
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }
        let carbonPoint = CGPoint(x: point.x, y: screen.frame.height - point.y - 1)
        
        guard let element = try? AXUIElement.systemWide().element(at: carbonPoint),
            let pid = try? element.pid() else {
            return false
        }
        
        return getpid() == pid
    }
}

private extension String {
    
    func components(options: String.EnumerationOptions) -> [String] {
        var components: [String] = []
        let range = Range(uncheckedBounds: (startIndex, endIndex))
        enumerateSubstrings(in: range, options: options) { _, _, range, _ in
            components.append(String(self[range]))
        }
        return components
    }
}
