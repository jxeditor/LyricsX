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
    private let spotifyClientTokenView = NSTextView()
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
        installScrollableLabControls()
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
        let tokens = SpotifyPrivateTokenResolver.normalizedTokens(
            accessTokenText: spotifyTokenView.string,
            clientTokenText: spotifyClientTokenView.string
        )
        defaults[.spotifyPrivateLyricsToken] = tokens.accessToken
        if let clientToken = tokens.clientToken {
            defaults[.spotifyPrivateLyricsClientToken] = clientToken
        }
        spotifyTokenView.string = defaults[.spotifyPrivateLyricsToken]
        spotifyClientTokenView.string = defaults[.spotifyPrivateLyricsClientToken]
        defaults[.spotifyPrivateLyricsTokenSavedAt] = Date()
        defaults[.spotifyPrivateLyricsStatus] = defaults[.spotifyPrivateLyricsToken].isEmpty ? "Token 已清空" : "Token 已保存"
        refreshSpotifyPanel()
    }

    @objc private func openSpotifyWebAction(_ sender: Any) {
        let result = SpotifyPrivateTokenResolver.openAndInstallCapture()
        defaults[.spotifyPrivateLyricsAutoResult] = result.message
        defaults[.spotifyPrivateLyricsStatus] = result.message
        refreshSpotifyPanel()
    }

    @objc private func readSpotifyTokenAction(_ sender: Any) {
        let result = SpotifyPrivateTokenResolver.readCapturedToken()
        defaults[.spotifyPrivateLyricsAutoResult] = result.message
        if let token = result.token {
            defaults[.spotifyPrivateLyricsToken] = token
            defaults[.spotifyPrivateLyricsTokenSavedAt] = Date()
            spotifyTokenView.string = token
        }
        if let clientToken = result.clientToken {
            defaults[.spotifyPrivateLyricsClientToken] = clientToken
            spotifyClientTokenView.string = clientToken
        }
        defaults[.spotifyPrivateLyricsStatus] = result.message
        refreshSpotifyPanel()
    }

    @objc private func refreshSpotifyPanelAction(_ sender: Any) {
        AppController.shared.currentTrackChanged()
        refreshSpotifyPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshSpotifyPanel()
        }
    }

    private func installScrollableLabControls() {
        let storyboardSubviews = view.subviews
        let storyboardConstraints = view.constraints
        NSLayoutConstraint.deactivate(storyboardConstraints)
        storyboardSubviews.forEach {
            $0.removeFromSuperview()
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let introLabel = storyboardSubviews
            .compactMap { $0 as? NSTextField }
            .max { $0.frame.width < $1.frame.width }
        introLabel?.maximumNumberOfLines = 0
        introLabel?.lineBreakMode = .byWordWrapping
        if let introLabel = introLabel {
            stack.addArrangedSubview(introLabel)
            introLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true
        }

        let optionStack = NSStackView()
        optionStack.orientation = .vertical
        optionStack.alignment = .leading
        optionStack.spacing = 10
        optionStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(optionStack)
        optionStack.widthAnchor.constraint(equalToConstant: 430).isActive = true

        let buttons = storyboardSubviews.compactMap { $0 as? NSButton }
        let customizeTouchBarButton = buttons.first { $0.bezelStyle == .rounded }
        let storyboardChecks = buttons
            .filter { $0 !== customizeTouchBarButton }
            .sorted { $0.frame.maxY > $1.frame.maxY }
        let oldChecks = storyboardChecks.filter { $0 !== enableTouchBarLyricsButton }

        oldChecks.prefix(2).forEach { optionStack.addArrangedSubview($0) }

        let touchBarRow = NSStackView()
        touchBarRow.orientation = .horizontal
        touchBarRow.alignment = .centerY
        touchBarRow.spacing = 12
        touchBarRow.addArrangedSubview(enableTouchBarLyricsButton)
        if let customizeTouchBarButton = customizeTouchBarButton {
            touchBarRow.addArrangedSubview(customizeTouchBarButton)
        }
        optionStack.addArrangedSubview(touchBarRow)

        if oldChecks.count >= 4 {
            let writeRow = NSStackView()
            writeRow.orientation = .horizontal
            writeRow.alignment = .top
            writeRow.spacing = 14

            let writeLabel = storyboardSubviews
                .compactMap { $0 as? NSTextField }
                .filter { $0 !== introLabel }
                .first
            writeLabel?.alignment = .right
            if let writeLabel = writeLabel {
                writeLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true
                writeRow.addArrangedSubview(writeLabel)
            }

            let writeOptions = NSStackView(views: Array(oldChecks[2...3]))
            writeOptions.orientation = .vertical
            writeOptions.alignment = .leading
            writeOptions.spacing = 8
            writeRow.addArrangedSubview(writeOptions)
            optionStack.addArrangedSubview(writeRow)
        }

        oldChecks.dropFirst(4).forEach { optionStack.addArrangedSubview($0) }

        let separator = NSBox()
        separator.boxType = .separator
        optionStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: optionStack.widthAnchor).isActive = true

        installExtraLabControls(in: optionStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -28),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func installExtraLabControls(in stack: NSStackView) {
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

        let tokenScrollView = NSScrollView()
        tokenScrollView.hasVerticalScroller = true
        tokenScrollView.hasHorizontalScroller = false
        tokenScrollView.autohidesScrollers = false
        tokenScrollView.borderType = .bezelBorder
        tokenScrollView.translatesAutoresizingMaskIntoConstraints = false
        configureTokenTextView(spotifyTokenView)
        spotifyTokenView.string = defaults[.spotifyPrivateLyricsToken]
        tokenScrollView.documentView = spotifyTokenView
        stack.addArrangedSubview(NSTextField(labelWithString: "Spotify authorization / access token"))
        stack.addArrangedSubview(tokenScrollView)

        let clientTokenScrollView = NSScrollView()
        clientTokenScrollView.hasVerticalScroller = true
        clientTokenScrollView.hasHorizontalScroller = false
        clientTokenScrollView.autohidesScrollers = false
        clientTokenScrollView.borderType = .bezelBorder
        clientTokenScrollView.translatesAutoresizingMaskIntoConstraints = false
        configureTokenTextView(spotifyClientTokenView)
        spotifyClientTokenView.string = defaults[.spotifyPrivateLyricsClientToken]
        clientTokenScrollView.documentView = spotifyClientTokenView
        stack.addArrangedSubview(NSTextField(labelWithString: "Spotify client-token"))
        stack.addArrangedSubview(clientTokenScrollView)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(NSButton(title: "打开 Spotify", target: self, action: #selector(openSpotifyWebAction(_:))))
        buttonRow.addArrangedSubview(NSButton(title: "读取 token", target: self, action: #selector(readSpotifyTokenAction(_:))))
        buttonRow.addArrangedSubview(NSButton(title: "保存 token", target: self, action: #selector(saveSpotifyTokenAction(_:))))
        buttonRow.addArrangedSubview(NSButton(title: "刷新状态", target: self, action: #selector(refreshSpotifyPanelAction(_:))))
        stack.addArrangedSubview(buttonRow)

        [spotifyAutoResultLabel, spotifySavedAtLabel, spotifyStatusLabel].forEach {
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 0
            stack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            tokenScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tokenScrollView.heightAnchor.constraint(equalToConstant: 96),
            clientTokenScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            clientTokenScrollView.heightAnchor.constraint(equalToConstant: 84)
        ])
    }

    private func configureTokenTextView(_ textView: NSTextView) {
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    private func refreshSpotifyPanel() {
        spotifyAutoResultLabel.stringValue = "Auto 结果：" + defaults[.spotifyPrivateLyricsAutoResult]
        if let savedAt = defaults[.spotifyPrivateLyricsTokenSavedAt] {
            spotifySavedAtLabel.stringValue = "保存时间：" + DateFormatter.localizedString(from: savedAt, dateStyle: .short, timeStyle: .medium)
        } else {
            spotifySavedAtLabel.stringValue = "保存时间：未保存"
        }
        let clientTokenStatus = defaults[.spotifyPrivateLyricsClientToken].isEmpty ? "未保存" : "已保存"
        spotifyStatusLabel.stringValue = "状态：" + defaults[.spotifyPrivateLyricsStatus] + "\nclient-token：" + clientTokenStatus
    }
}

private enum SpotifyPrivateTokenResolver {
    static func normalizedTokens(accessTokenText: String, clientTokenText: String) -> (accessToken: String, clientToken: String?) {
        let lines = accessTokenText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var accessToken: String?
        var clientToken: String?
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if lower == "authorization", lines.indices.contains(index + 1) {
                accessToken = normalizedAccessToken(lines[index + 1])
            } else if lower.hasPrefix("authorization:") {
                accessToken = normalizedAccessToken(String(line.dropFirst("authorization:".count)))
            } else if lower.hasPrefix("bearer ") {
                accessToken = normalizedAccessToken(line)
            } else if lower == "client-token", lines.indices.contains(index + 1) {
                clientToken = lines[index + 1]
            } else if lower.hasPrefix("client-token:") {
                clientToken = String(line.dropFirst("client-token:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let explicitClientToken = clientTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (accessToken ?? normalizedAccessToken(accessTokenText), explicitClientToken.isEmpty ? clientToken : explicitClientToken)
    }

    static func normalizedAccessToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func openAndInstallCapture() -> (token: String?, clientToken: String?, message: String) {
        guard let spotifyURL = URL(string: "https://open.spotify.com/") else {
            return (nil, nil, "Spotify 地址无效")
        }
        NSWorkspace.shared.open(spotifyURL)

        let result = executeChromeCaptureScript()
        if result.message.contains("已从 Chrome Spotify 页面读取") {
            return result
        }
        return (nil, nil, "已打开 Spotify。请在网页播放/刷新后点击“读取 token”")
    }

    static func readCapturedToken() -> (token: String?, clientToken: String?, message: String) {
        let chromeResult = executeChromeCaptureScript()
        if chromeResult.token != nil || chromeResult.clientToken != nil {
            return chromeResult
        }
        let cacheResult = readChromeCacheTokens()
        if cacheResult.token != nil || cacheResult.clientToken != nil {
            return cacheResult
        }
        return chromeResult.message.contains("JavaScript")
            ? (nil, nil, "Chrome JS 不可用，且缓存中未找到可用 token")
            : chromeResult
    }

    private static func executeChromeCaptureScript() -> (token: String?, clientToken: String?, message: String) {
        let script = chromeCaptureScript()
        let appleScript = """
        tell application "Google Chrome"
            set targetTab to missing value
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t starts with "https://open.spotify.com" then
                        set targetTab to t
                        exit repeat
                    end if
                end repeat
                if targetTab is not missing value then exit repeat
            end repeat
            if targetTab is missing value then
                return "NEED_OPEN"
            end if
            return execute targetTab javascript \(appleScriptLiteral(script))
        end tell
        """

        guard let output = runAppleScript(appleScript) else {
            return (nil, nil, "无法读取 Chrome。请在 Chrome 菜单启用：查看 > 开发者 > 允许 Apple 事件中的 JavaScript")
        }
        if output.contains("Apple 事件中的 JavaScript") || output.contains("JavaScript") && output.contains("关闭") {
            return (nil, nil, "Chrome 禁止 AppleScript 执行 JS：请启用 查看 > 开发者 > 允许 Apple 事件中的 JavaScript")
        }
        if output == "NEED_OPEN" || output.contains("NEED_OPEN") {
            return (nil, nil, "已打开 Spotify，请登录/播放后再点一次读取")
        }
        guard let data = output.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, "已注入捕获脚本。请在 Spotify 网页播放/刷新后再点一次读取")
        }
        let token = payload["authorization"] as? String
        let clientToken = payload["clientToken"] as? String
        if let token = token, !token.isEmpty {
            let cleanedToken = normalizedAccessToken(token)
            return (cleanedToken, clientToken, "已从 Chrome Spotify 页面读取 authorization")
        }
        return (nil, clientToken, "已注入捕获脚本。请在 Spotify 网页播放/刷新后再点一次读取")
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let result = script.executeAndReturnError(&error).stringValue else {
            return error?.description
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appleScriptLiteral(_ text: String) -> String {
        "\"" + text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }

    private static func chromeCaptureScript() -> String {
        """
        (() => {
          if (!window.__lyricsXSpotifyHeaderCaptureInstalled) {
            window.__lyricsXSpotifyHeaderCaptureInstalled = true;
            window.__lyricsXSpotifyHeaders = window.__lyricsXSpotifyHeaders || {};
            window.__lyricsXSpotifyCaptureInstalledAt = Date.now();
            const remember = (headers) => {
              if (!headers) return;
              try {
                if (headers instanceof Headers) {
                  const authorization = headers.get('authorization');
                  const clientToken = headers.get('client-token') || headers.get('Client-Token') || headers.get('clientToken');
                  if (authorization) window.__lyricsXSpotifyHeaders.authorization = authorization;
                  if (clientToken) window.__lyricsXSpotifyHeaders.clientToken = clientToken;
                  return;
                }
                if (Array.isArray(headers)) {
                  headers.forEach(([key, value]) => {
                    key = String(key).toLowerCase();
                    if (key === 'authorization') window.__lyricsXSpotifyHeaders.authorization = value;
                    if (key === 'client-token' || key === 'clienttoken') window.__lyricsXSpotifyHeaders.clientToken = value;
                  });
                  return;
                }
                Object.keys(headers).forEach((key) => {
                  const lower = key.toLowerCase();
                  if (lower === 'authorization') window.__lyricsXSpotifyHeaders.authorization = headers[key];
                  if (lower === 'client-token' || lower === 'clienttoken') window.__lyricsXSpotifyHeaders.clientToken = headers[key];
                });
              } catch (_) {}
            };
            const originalFetch = window.fetch;
            window.fetch = function(input, init) {
              try {
                remember(init && init.headers);
                remember(input && input.headers);
              } catch (_) {}
              return originalFetch.apply(this, arguments);
            };
            const originalOpen = XMLHttpRequest.prototype.open;
            const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
            XMLHttpRequest.prototype.open = function() {
              this.__lyricsXSpotifyHeaders = {};
              return originalOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.setRequestHeader = function(key, value) {
              try {
                const lower = String(key).toLowerCase();
                if (lower === 'authorization') window.__lyricsXSpotifyHeaders.authorization = value;
                if (lower === 'client-token' || lower === 'clienttoken') window.__lyricsXSpotifyHeaders.clientToken = value;
              } catch (_) {}
              return originalSetRequestHeader.apply(this, arguments);
            };
          }
          try {
            fetch('/api/me').catch(() => {});
            fetch('/api/token').catch(() => {});
            const scripts = Array.from(document.scripts || []).map((script) => script.textContent || '').join('\\n');
            const clientTokenMatch = scripts.match(/client-token["']?\\s*[:=]\\s*["']([^"']+)/i) || scripts.match(/clientToken["']?\\s*[:=]\\s*["']([^"']+)/i);
            if (clientTokenMatch && clientTokenMatch[1]) window.__lyricsXSpotifyHeaders.clientToken = clientTokenMatch[1];
          } catch (_) {}
          return JSON.stringify(window.__lyricsXSpotifyHeaders || {});
        })()
        """
    }

    private static func readChromeCacheTokens() -> (token: String?, clientToken: String?, message: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let chromeDefault = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        let roots = [
            chromeDefault.appendingPathComponent("Service Worker/CacheStorage"),
            chromeDefault.appendingPathComponent("Local Storage/leveldb"),
            chromeDefault.appendingPathComponent("Session Storage"),
            chromeDefault.appendingPathComponent("IndexedDB/https_open.spotify.com_0.indexeddb.leveldb")
        ]

        var candidates: [(url: URL, modified: Date)] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize > 0,
                      fileSize <= 20_000_000 else {
                    continue
                }
                candidates.append((fileURL, values.contentModificationDate ?? .distantPast))
            }
        }

        var tokens: [String] = []
        var clientTokens: [String] = []
        for candidate in candidates.sorted(by: { $0.modified > $1.modified }) {
            guard (tokens.count < 40 || clientTokens.count < 20),
                  let data = try? Data(contentsOf: candidate.url, options: [.mappedIfSafe]),
                  containsSpotifyHint(data) else {
                continue
            }
            for token in extractAccessTokens(from: data) where !tokens.contains(token) {
                tokens.append(token)
            }
            for clientToken in extractClientTokens(from: data) where !clientTokens.contains(clientToken) {
                clientTokens.append(clientToken)
            }
        }

        if let trackID = currentSpotifyTrackID(),
           let validated = validateSpotifyLyricsToken(tokens: tokens, clientTokens: clientTokens, trackID: trackID) {
            return (validated.token, validated.clientToken, "已从 Chrome 缓存读取并验证 Spotify 歌词 token")
        }

        let token = tokens.first
        let clientToken = clientTokens.first
        switch (token, clientToken) {
        case (.some, .some):
            return (token, clientToken, "已从 Chrome 缓存读取 authorization 和 client-token，但未通过歌词接口验证")
        case (.some, .none):
            return (token, nil, "已从 Chrome 缓存读取 authorization，未找到 client-token，且未通过歌词接口验证")
        case (.none, .some):
            return (nil, clientToken, "已从 Chrome 缓存读取 client-token，未找到 authorization")
        case (.none, .none):
            return (nil, nil, "Chrome 缓存中未找到 Spotify token")
        }
    }

    private static func containsSpotifyHint(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(200_000), encoding: .utf8) else {
            return data.range(of: Data("spotify".utf8)) != nil ||
                data.range(of: Data("Bearer BQ".utf8)) != nil ||
                data.range(of: Data("client-token".utf8)) != nil
        }
        return text.localizedCaseInsensitiveContains("spotify") ||
            text.contains("Bearer BQ") ||
            text.localizedCaseInsensitiveContains("client-token") ||
            text.localizedCaseInsensitiveContains("clientToken")
    }

    private static func extractAccessTokens(from data: Data) -> [String] {
        let bytes = [UInt8](data)
        var tokens: [String] = []
        let patterns = ["Bearer BQ", "\"accessToken\"", "accessToken"]
        for pattern in patterns {
            guard let range = data.range(of: Data(pattern.utf8)) else {
                continue
            }
            let start = range.lowerBound
            let windowEnd = min(bytes.count, start + 20_000)
            let window = String(decoding: bytes[start..<windowEnd], as: UTF8.self)
            for token in matches(in: window, pattern: #"Bearer\s+(BQ[A-Za-z0-9_-]{80,})"#) where !tokens.contains(token) {
                tokens.append(token)
            }
            for token in matches(in: window, pattern: #""accessToken"\s*:\s*"(BQ[A-Za-z0-9_-]{80,})""#) where !tokens.contains(token) {
                tokens.append(token)
            }
            for token in matches(in: window, pattern: #"accessToken[^A-Za-z0-9_-]+(BQ[A-Za-z0-9_-]{80,})"#) where !tokens.contains(token) {
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func extractClientTokens(from data: Data) -> [String] {
        let bytes = [UInt8](data)
        var tokens: [String] = []
        for pattern in ["client-token", "Client-Token", "clientToken"] {
            guard let range = data.range(of: Data(pattern.utf8)) else {
                continue
            }
            let start = range.lowerBound
            let windowEnd = min(bytes.count, start + 20_000)
            let window = String(decoding: bytes[start..<windowEnd], as: UTF8.self)
            for token in matches(in: window, pattern: #"client-token[^A-Za-z0-9+/=]+([A-Za-z0-9+/=]{80,})"#) where !tokens.contains(token) {
                tokens.append(token)
            }
            for token in matches(in: window, pattern: #"Client-Token[^A-Za-z0-9+/=]+([A-Za-z0-9+/=]{80,})"#) where !tokens.contains(token) {
                tokens.append(token)
            }
            for token in matches(in: window, pattern: #"clientToken[^A-Za-z0-9+/=]+([A-Za-z0-9+/=]{80,})"#) where !tokens.contains(token) {
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func currentSpotifyTrackID() -> String? {
        guard let track = selectedPlayer.currentTrack else {
            return nil
        }
        if selectedPlayer.name == .spotify || track.id.hasPrefix("spotify:track:") {
            return track.id.replacingOccurrences(of: "spotify:track:", with: "")
        }
        return nil
    }

    private static func validateSpotifyLyricsToken(tokens: [String], clientTokens: [String], trackID: String) -> (token: String, clientToken: String?)? {
        let clientCandidates: [String?] = clientTokens.isEmpty ? [nil] : clientTokens.map(Optional.some) + [nil]
        for token in tokens.prefix(20) {
            for clientToken in clientCandidates.prefix(8) where canFetchSpotifyLyrics(trackID: trackID, token: token, clientToken: clientToken) {
                return (token, clientToken)
            }
        }
        return nil
    }

    private static func canFetchSpotifyLyrics(trackID: String, token: String, clientToken: String?) -> Bool {
        var components = URLComponents(string: "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(trackID)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "vocalRemoval", value: "false"),
            URLQueryItem(name: "market", value: "from_token")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 4
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let clientToken = clientToken {
            request.setValue(clientToken, forHTTPHeaderField: "client-token")
            request.setValue(clientToken, forHTTPHeaderField: "Client-Token")
        }
        request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")
        request.setValue("https://open.spotify.com/", forHTTPHeaderField: "Referer")
        request.setValue("WebPlayer", forHTTPHeaderField: "app-platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        request.setValue("1.2.91.110.g17202b22", forHTTPHeaderField: "spotify-app-version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var isValid = false
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(statusCode),
               let data = data,
               data.range(of: Data(#""lyrics""#.utf8)) != nil {
                isValid = true
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return isValid
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
