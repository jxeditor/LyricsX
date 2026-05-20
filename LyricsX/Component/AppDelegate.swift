//
//  AppDelegate.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Cocoa
import GenericID
import LyricsService
import MASShortcut
import MusicPlayer
#if ENABLE_APPCENTER && canImport(AppCenter) && canImport(AppCenterAnalytics) && canImport(AppCenterCrashes)
import AppCenter
import AppCenterAnalytics
import AppCenterCrashes
#endif

#if !IS_FOR_MAS
import Sparkle
#endif

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    
    static var shared: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    
    @IBOutlet weak var lyricsOffsetTextField: NSTextField!
    @IBOutlet weak var lyricsOffsetStepper: NSStepper!
    @IBOutlet weak var statusBarMenu: NSMenu!
    
    var karaokeLyricsWC: KaraokeLyricsWindowController?
    
    lazy var searchLyricsWC: NSWindowController = {
        // swiftlint:disable:next force_cast
        let searchVC = NSStoryboard.main!.instantiateController(withIdentifier: .init("SearchLyricsViewController")) as! SearchLyricsViewController
        let window = NSWindow(contentViewController: searchVC)
        window.title = NSLocalizedString("Search Lyrics", comment: "window title")
        return NSWindowController(window: window)
    }()
    
    lazy var preferencesWC: NSWindowController = {
        // swiftlint:disable:next force_cast
        NSStoryboard(name: "Preferences", bundle: nil).instantiateInitialController() as! NSWindowController
    }()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerUserDefaults()
        configureLyricsProviders()
        #if RELEASE && ENABLE_APPCENTER && canImport(AppCenter) && canImport(AppCenterAnalytics) && canImport(AppCenterCrashes)
        AppCenter.start(withAppSecret: "36777a05-06fd-422e-9375-a934b3c835a5", services:[
            Analytics.self,
            Crashes.self
        ])
        #endif
        
        let controller = AppController.shared
        
        karaokeLyricsWC = KaraokeLyricsWindowController()
        karaokeLyricsWC?.showWindow(nil)
        
        statusBarMenu.delegate = self
        installMainMenuFallback()
        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        launchMenuBarHelper()
        
        lyricsOffsetStepper.bind(.value,
                                 to: controller,
                                 withKeyPath: #keyPath(AppController.lyricsOffset),
                                 options: [.continuouslyUpdatesValue: true])
        lyricsOffsetTextField.bind(.value,
                                   to: controller,
                                   withKeyPath: #keyPath(AppController.lyricsOffset),
                                   options: [.continuouslyUpdatesValue: true])
        
        setupShortcuts()
        
        let sharedKeys: [UserDefaults.DefaultsKeys] = [
            .launchAndQuitWithPlayer,
            .preferredPlayerIndex,
        ]
        sharedKeys.forEach {
            groupDefaults.bind(NSBindingName($0.key), withDefaultName: $0)
        }
        
        #if IS_FOR_MAS
        checkForMASReview(force: true)
        #else
        SUUpdater.shared()?.automaticallyChecksForUpdates = false
        if #available(OSX 10.12.2, *) {
            observeDefaults(key: .touchBarLyricsEnabled, options: [.new, .initial]) { _, change in
                if change.newValue, TouchBarLyricsController.shared == nil {
                    TouchBarLyricsController.shared = TouchBarLyricsController()
                } else if !change.newValue, TouchBarLyricsController.shared != nil {
                    TouchBarLyricsController.shared = nil
                }
            }
        }
        #endif
    }

    private func launchMenuBarHelper() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: lyricsXHelperIdentifier).isEmpty else {
            return
        }
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/LyricsXHelper.app")
        try? NSWorkspace.shared.launchApplication(at: url, configuration: [:])
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        if AppController.shared.currentLyrics?.metadata.needsPersist == true {
            AppController.shared.currentLyrics?.persist()
        }
        if defaults[.launchAndQuitWithPlayer] {
            let url = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LoginItems/LyricsXHelper.app")
            groupDefaults[.launchHelperTime] = Date()
            do {
                try NSWorkspace.shared.launchApplication(at: url, configuration: [:])
                log("launch LyricsX Helper succeed.")
            } catch {
                log("launch LyricsX Helper failed. reason: \(error)")
            }
        }
    }
    
    private func setupShortcuts() {
        let binder = MASShortcutBinder.shared()!
        binder.bindBoolShortcut(.shortcutToggleMenuBarLyrics, target: .menuBarLyricsEnabled)
        binder.bindBoolShortcut(.shortcutToggleKaraokeLyrics, target: .desktopLyricsEnabled)
        binder.bindShortcut(.shortcutShowLyricsWindow, to: #selector(showLyricsHUD))
        binder.bindShortcut(.shortcutOffsetIncrease, to: #selector(increaseOffset))
        binder.bindShortcut(.shortcutOffsetDecrease, to: #selector(decreaseOffset))
        binder.bindShortcut(.shortcutWriteToiTunes, to: #selector(writeToiTunes))
        binder.bindShortcut(.shortcutWrongLyrics, to: #selector(wrongLyrics))
        binder.bindShortcut(.shortcutSearchLyrics, to: #selector(searchLyrics))
    }
    
    // MARK: - NSMenuDelegate
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(writeToiTunes(_:))?:
            return selectedPlayer.name == .appleMusic && AppController.shared.currentLyrics != nil
        case #selector(searchLyrics(_:))?:
            return selectedPlayer.currentTrack != nil
        default:
            return true
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 202)?.isEnabled = AppController.shared.currentLyrics != nil
    }
    
    private func installMainMenuFallback() {
        guard let mainMenu = NSApp.mainMenu else {
            return
        }
        
        let menuItem = NSMenuItem(title: "LyricsX", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "LyricsX")
        menu.delegate = self
        menuItem.submenu = menu
        
        menu.addItem(makeToggleMenuItem(title: localizedMainMenuTitle("Enable Menu Bar Lyrics"), key: .menuBarLyricsEnabled))
        menu.addItem(makeToggleMenuItem(title: localizedMainMenuTitle("Enable Karaoke Lyrics"), key: .desktopLyricsEnabled))
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("Show Lyrics Window"), action: #selector(showLyricsHUD(_:)), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("Search Lyrics..."), action: #selector(searchLyrics(_:)), keyEquivalent: "f"))
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("Wrong Lyrics"), action: #selector(wrongLyrics(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("Write to iTunes"), action: #selector(writeToiTunes(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("Preferences..."), action: #selector(showPreferences(_:)), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("About LyricsX"), action: #selector(aboutLyricsXAction(_:)), keyEquivalent: ""))
        #if !IS_FOR_MAS
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("Check For Update..."), action: #selector(checkUpdateAction(_:)), keyEquivalent: ""))
        #endif
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: localizedMainMenuTitle("Quit LyricsX"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        let insertIndex = min(1, mainMenu.items.count)
        mainMenu.insertItem(menuItem, at: insertIndex)
    }
    
    private func makeToggleMenuItem(title: String, key: UserDefaults.DefaultsKey<Bool>) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleDefaultMenuItem(_:)), keyEquivalent: "")
        item.representedObject = key.key
        item.state = defaults[key] ? .on : .off
        return item
    }
    
    private func localizedMainMenuTitle(_ title: String) -> String {
        return Bundle.main.localizedString(forKey: title, value: title, table: "Main")
    }
    
    @objc private func toggleDefaultMenuItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else {
            return
        }
        let defaultsKey = UserDefaults.DefaultsKey<Bool>(key)
        defaults[defaultsKey] = !defaults[defaultsKey]
        sender.state = defaults[defaultsKey] ? .on : .off
    }
    
    // MARK: - Menubar Action
    
    var lyricsHUD: NSWindowController?
    
    @IBAction func showLyricsHUD(_ sender: Any?) {
        // swiftlint:disable:next force_cast
        let controller = lyricsHUD ?? NSStoryboard.main?.instantiateController(withIdentifier: .init("LyricsHUD")) as! NSWindowController
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        lyricsHUD = controller
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "lyricsx" else {
            return
        }
        switch url.host {
        case "show-lyrics-window":
            showLyricsHUD(nil)
        case "preferences":
            showPreferences(nil)
        case "search":
            searchLyrics(nil)
        case "toggle-menu-bar-lyrics":
            defaults[.menuBarLyricsEnabled] = !defaults[.menuBarLyricsEnabled]
        case "toggle-desktop-lyrics":
            defaults[.desktopLyricsEnabled] = !defaults[.desktopLyricsEnabled]
        case "quit":
            NSApp.terminate(nil)
        default:
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @IBAction func showPreferences(_ sender: Any?) {
        preferencesWC.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func aboutLyricsXAction(_ sender: Any) {
        if #available(OSX 10.13, *) {
            #if IS_FOR_MAS
                let channel = "App Store"
            #else
                let channel = "GitHub"
            #endif
            let version = Bundle.main.semanticVersion.map(String.init) ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            let versionString = "\(channel) Version \(version)"
            NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: versionString])
        } else {
            NSApp.orderFrontStandardAboutPanel(sender)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func checkUpdateAction(_ sender: Any) {
        #if IS_FOR_MAS
        assert(false, "should not be there")
        #else
        SUUpdater.shared()?.checkForUpdates(sender)
        #endif
    }
    
    @IBAction func increaseOffset(_ sender: Any?) {
        AppController.shared.lyricsOffset += 100
    }
    
    @IBAction func decreaseOffset(_ sender: Any?) {
        AppController.shared.lyricsOffset -= 100
    }
    
    @IBAction func showCurrentLyricsInFinder(_ sender: Any?) {
        guard let lyrics = AppController.shared.currentLyrics else {
            return
        }
        if lyrics.metadata.needsPersist {
            lyrics.persist()
        }
        if let url = lyrics.metadata.localURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    @IBAction func writeToiTunes(_ sender: Any?) {
        AppController.shared.writeToiTunes(overwrite: true)
    }
    
    @IBAction func searchLyrics(_ sender: Any?) {
        searchLyricsWC.window?.makeKeyAndOrderFront(nil)
        (searchLyricsWC.contentViewController as! SearchLyricsViewController?)?.reloadKeyword()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func wrongLyrics(_ sender: Any?) {
        guard let track = selectedPlayer.currentTrack else {
            return
        }
        defaults[.noSearchingTrackIds].append(track.id)
        if defaults[.writeToiTunesAutomatically] {
            track.setLyrics("")
        }
        if let url = AppController.shared.currentLyrics?.metadata.localURL {
            try? FileManager.default.removeItem(at: url)
        }
        AppController.shared.currentLyrics = nil
        AppController.shared.searchCanceller?.cancel()
    }
    
    @IBAction func doNotSearchLyricsForThisAlbum(_ sender: Any?) {
        guard let track = selectedPlayer.currentTrack,
            let album = track.album else {
            return
        }
        defaults[.noSearchingAlbumNames].append(album)
        if defaults[.writeToiTunesAutomatically] {
            track.setLyrics("")
        }
        if let url = AppController.shared.currentLyrics?.metadata.localURL {
            try? FileManager.default.removeItem(at: url)
        }
        AppController.shared.currentLyrics = nil
    }
    
    func registerUserDefaults() {
        let currentLang = NSLocale.preferredLanguages.first!
        let isZh = currentLang.hasPrefix("zh") || currentLang.hasPrefix("yue")
        let isHant = isZh && (currentLang.contains("-Hant") || currentLang.contains("-HK"))
        
        let defaultsUrl = Bundle.main.url(forResource: "UserDefaults", withExtension: "plist")!
        if let dict = NSDictionary(contentsOf: defaultsUrl) as? [String: Any] {
            defaults.register(defaults: dict)
        }
        defaults.register(defaults: [
            .desktopLyricsColor: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1),
            .desktopLyricsProgressColor: #colorLiteral(red: 0.1985405816, green: 1, blue: 0.8664234302, alpha: 1),
            .desktopLyricsShadowColor: #colorLiteral(red: 0, green: 1, blue: 0.8333333333, alpha: 1),
            .desktopLyricsBackgroundColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.6041579279),
            .lyricsWindowTextColor: #colorLiteral(red: 0.7540688515, green: 0.7540867925, blue: 0.7540771365, alpha: 1),
            .lyricsWindowHighlightColor: #colorLiteral(red: 0.8866666667, green: 1, blue: 0.8, alpha: 1),
            .preferBilingualLyrics: isZh,
            .chineseConversionIndex: isHant ? 2 : 0,
            .desktopLyricsXPositionFactor: 0.5,
            .desktopLyricsYPositionFactor: 0.9,
            .desktopLyricsFixedWidthEnabled: false,
            .desktopLyricsFixedWidth: 960,
            .autoTimingLyricsEnabled: false,
            .spotifyPrivateLyricsEnabled: false,
            .spotifyPrivateLyricsToken: "",
            .spotifyPrivateLyricsClientToken: "",
            .spotifyPrivateLyricsAutoResult: "",
            .spotifyPrivateLyricsStatus: "",
        ])
    }

    private func configureLyricsProviders() {
        LyricsProviders.SpotifyPrivate.accessTokenProvider = {
            defaults[.spotifyPrivateLyricsEnabled] ? defaults[.spotifyPrivateLyricsToken] : nil
        }
        LyricsProviders.SpotifyPrivate.clientTokenProvider = {
            defaults[.spotifyPrivateLyricsEnabled] ? defaults[.spotifyPrivateLyricsClientToken] : nil
        }
        LyricsProviders.SpotifyPrivate.imageURLProvider = {
            guard defaults[.spotifyPrivateLyricsEnabled],
                  selectedPlayer.name == .spotify,
                  let track = selectedPlayer.currentTrack,
                  let sbTrack = track.originalSBTrack,
                  let artworkURL = sbTrack.value(forKey: "artworkUrl") as? String,
                  !artworkURL.isEmpty else {
                return nil
            }
            return artworkURL
        }
        LyricsProviders.SpotifyPrivate.statusHandler = { status in
            DispatchQueue.main.async {
                defaults[.spotifyPrivateLyricsStatus] = status
            }
        }
    }
}

extension MASShortcutBinder {
    
    func bindShortcut<T>(_ defaultsKay: UserDefaults.DefaultsKey<T>, to action: @escaping () -> Void) {
        bindShortcut(withDefaultsKey: defaultsKay.key, toAction: action)
    }
    
    func bindBoolShortcut<T>(_ defaultsKay: UserDefaults.DefaultsKey<T>, target: UserDefaults.DefaultsKey<Bool>) {
        bindShortcut(withDefaultsKey: defaultsKay.key) {
            defaults[target] = !defaults[target]
        }
    }
    
    func bindShortcut<T>(_ defaultsKay: UserDefaults.DefaultsKey<T>, to action: Selector) {
        bindShortcut(defaultsKay) {
            let target = NSApplication.shared.target(forAction: action) as AnyObject?
            _ = target?.perform(action, with: self)
        }
    }
}
