//
//  PreferenceLabViewController.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Cocoa

class PreferenceLabViewController: NSViewController {
    
    @IBOutlet weak var enableTouchBarLyricsButton: NSButton!
    private let spotifyTokenView = NSTextView()
    private let spotifyAutoResultLabel = NSTextField(labelWithString: "")
    private let spotifySavedAtLabel = NSTextField(labelWithString: "")
    private let spotifyStatusLabel = NSTextField(labelWithString: "")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        #if IS_FOR_MAS
            enableTouchBarLyricsButton.state = .off
            enableTouchBarLyricsButton.target = self
            enableTouchBarLyricsButton.action = #selector(mas_enableTouchBarLyricsAction)
        #else
            enableTouchBarLyricsButton.bind(.value, withDefaultName: .touchBarLyricsEnabled)
        #endif
        installExtraLabControls()
        refreshSpotifyPanel()
    }
    
    @IBAction func mas_enableTouchBarLyricsAction(_ sender: NSButton) {
        sender.state = .off
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Unable to enable Touch Bar lyrics.", comment: "alert title")
        alert.informativeText = NSLocalizedString("Touch Bar lyrics is not supported in Mac App Store Version. Please download on GitHub.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Download", comment: ""))
        let handler = { (response: NSApplication.ModalResponse) in
            if response == .alertSecondButtonReturn {
                let url = URL(string: "https://github.com/XQS6LB3A/LyricsX/releases")!
                NSWorkspace.shared.open(url)
            }
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
    
    @IBAction func customizeTouchBarAction(_ sender: NSButton) {
        if #available(OSX 10.12.2, *) {
            NSApplication.shared.toggleTouchBarCustomizationPalette(sender)
        } else {
            // Fallback on earlier versions
        }
    }

    @objc private func saveSpotifyTokenAction(_ sender: Any) {
        defaults[.spotifyPrivateLyricsToken] = spotifyTokenView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults[.spotifyPrivateLyricsTokenSavedAt] = Date()
        defaults[.spotifyPrivateLyricsStatus] = defaults[.spotifyPrivateLyricsToken].isEmpty ? "Token 已清空" : "Token 已保存"
        refreshSpotifyPanel()
    }

    @objc private func autoSpotifyTokenAction(_ sender: Any) {
        let result = SpotifyPrivateTokenResolver.resolve()
        defaults[.spotifyPrivateLyricsAutoResult] = result.message
        if let token = result.token {
            defaults[.spotifyPrivateLyricsToken] = token
            defaults[.spotifyPrivateLyricsTokenSavedAt] = Date()
            spotifyTokenView.string = token
        }
        defaults[.spotifyPrivateLyricsStatus] = result.message
        refreshSpotifyPanel()
    }

    @objc private func refreshSpotifyPanelAction(_ sender: Any) {
        refreshSpotifyPanel()
    }

    private func installExtraLabControls() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let autoTiming = NSButton(checkboxWithTitle: "自动打轴", target: nil, action: nil)
        autoTiming.bind(.value, withDefaultName: .autoTimingLyricsEnabled)
        stack.addArrangedSubview(autoTiming)

        let fixedWidthRow = NSStackView()
        fixedWidthRow.orientation = .horizontal
        fixedWidthRow.alignment = .centerY
        fixedWidthRow.spacing = 8
        let fixedWidth = NSButton(checkboxWithTitle: "固定桌面歌词宽度", target: nil, action: nil)
        fixedWidth.bind(.value, withDefaultName: .desktopLyricsFixedWidthEnabled)
        let widthField = NSTextField()
        widthField.formatter = NumberFormatter()
        widthField.alignment = .right
        widthField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        widthField.bind(.value, withDefaultName: .desktopLyricsFixedWidth)
        fixedWidthRow.addArrangedSubview(fixedWidth)
        fixedWidthRow.addArrangedSubview(widthField)
        fixedWidthRow.addArrangedSubview(NSTextField(labelWithString: "px"))
        stack.addArrangedSubview(fixedWidthRow)

        let spotifyEnabled = NSButton(checkboxWithTitle: "启用 Spotify private lyrics", target: nil, action: nil)
        spotifyEnabled.bind(.value, withDefaultName: .spotifyPrivateLyricsEnabled)
        stack.addArrangedSubview(spotifyEnabled)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        spotifyTokenView.isHorizontallyResizable = true
        spotifyTokenView.isVerticallyResizable = true
        spotifyTokenView.minSize = NSSize(width: 0, height: 0)
        spotifyTokenView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        spotifyTokenView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        spotifyTokenView.textContainer?.widthTracksTextView = false
        spotifyTokenView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        spotifyTokenView.string = defaults[.spotifyPrivateLyricsToken]
        scrollView.documentView = spotifyTokenView
        stack.addArrangedSubview(NSTextField(labelWithString: "Spotify token 明文"))
        stack.addArrangedSubview(scrollView)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(NSButton(title: "自动获取", target: self, action: #selector(autoSpotifyTokenAction(_:))))
        buttonRow.addArrangedSubview(NSButton(title: "保存 token", target: self, action: #selector(saveSpotifyTokenAction(_:))))
        buttonRow.addArrangedSubview(NSButton(title: "刷新状态", target: self, action: #selector(refreshSpotifyPanelAction(_:))))
        stack.addArrangedSubview(buttonRow)

        [spotifyAutoResultLabel, spotifySavedAtLabel, spotifyStatusLabel].forEach {
            $0.lineBreakMode = .byTruncatingMiddle
            stack.addArrangedSubview($0)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 234),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 260),
            scrollView.widthAnchor.constraint(equalToConstant: 340),
            scrollView.heightAnchor.constraint(equalToConstant: 92),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 620)
        ])
    }

    private func refreshSpotifyPanel() {
        spotifyAutoResultLabel.stringValue = "Auto 结果：" + defaults[.spotifyPrivateLyricsAutoResult]
        if let savedAt = defaults[.spotifyPrivateLyricsTokenSavedAt] {
            spotifySavedAtLabel.stringValue = "保存时间：" + DateFormatter.localizedString(from: savedAt, dateStyle: .short, timeStyle: .medium)
        } else {
            spotifySavedAtLabel.stringValue = "保存时间：未保存"
        }
        spotifyStatusLabel.stringValue = "状态：" + defaults[.spotifyPrivateLyricsStatus]
    }
}

private enum SpotifyPrivateTokenResolver {
    static func resolve() -> (token: String?, message: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/Spotify/PersistentCache/Users"),
            home.appendingPathComponent("Library/Application Support/Spotify")
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            if let token = findToken(in: candidate) {
                return (token, "已从 Spotify 本地缓存读取 token")
            }
        }
        return (nil, "未找到 Spotify 本地 token，请手动粘贴")
    }

    private static func findToken(in root: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
                  data.count < 2_000_000,
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            if let token = extractToken(from: text) {
                return token
            }
        }
        return nil
    }

    private static func extractToken(from text: String) -> String? {
        let pattern = #""accessToken"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
