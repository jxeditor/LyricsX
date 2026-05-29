//
//  PreferenceGeneralViewController.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Cocoa
import MusicPlayer
import ServiceManagement

class PreferenceGeneralViewController: NSViewController {
    
    @IBOutlet weak var preferAuto: NSButton!
    @IBOutlet weak var preferiTunes: NSButton!
    @IBOutlet weak var preferSpotify: NSButton!
    @IBOutlet weak var preferNetEase: NSButton?
    @IBOutlet weak var preferVox: NSButton!
    @IBOutlet weak var preferAudirvana: NSButton!
    @IBOutlet weak var preferSwinsian: NSButton!
    
    @IBOutlet weak var autoLaunchButton: NSButton!
    
    @IBOutlet weak var savingPathPopUp: NSPopUpButton!
    @IBOutlet weak var userPathMenuItem: NSMenuItem!
    
    @IBOutlet weak var loadHomonymLrcButton: NSButton!
    
    @IBOutlet weak var languagePopUp: NSPopUpButton!

    private var preferredPlayerButtons: [NSButton] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        installPreferredPlayerControls()
        
        switch defaults[.preferredPlayerIndex] {
        case 0:
            preferiTunes.state = .on
        case 1:
            preferSpotify.state = .on
            loadHomonymLrcButton.isEnabled = false
        case 2:
            preferVox.state = .on
        case 3:
            preferAudirvana.state = .on
            loadHomonymLrcButton.isEnabled = false
        case 4:
            preferSwinsian.state = .on
        default:
            preferAuto.state = .on
            autoLaunchButton.isEnabled = false
        }
        
        if let url = defaults.lyricsCustomSavingPath {
            userPathMenuItem.title = url.lastPathComponent
            userPathMenuItem.toolTip = url.path
        } else {
            userPathMenuItem.isHidden = true
        }
        
        let localizedLan: [String] = localizations.map { lan in
            if let idx = lan.firstIndex(of: "-") {
                let script = lan[idx...].dropFirst()
                return Locale(identifier: lan).localizedString(forScriptCode: String(script))!
            } else {
                return Locale(identifier: lan).localizedString(forLanguageCode: lan)!
            }
        }
        languagePopUp.addItems(withTitles: localizedLan)
        
        if let lan = defaults[.selectedLanguage],
            let idx = localizations.firstIndex(of: lan) {
            languagePopUp.selectItem(at: idx + 2)
        }
        syncPreferredPlayerButtons()
    }
    
    @IBAction func toggleAutoLaunchAction(_ sender: NSButton) {
        let enabled = sender.state == .on
        if !SMLoginItemSetEnabled(lyricsXHelperIdentifier as CFString, enabled) {
            log("Failed to set login item enabled")
        }
    }
    
    @IBAction func showInFinderAction(_ sender: Any) {
        let url = defaults.lyricsSavingPath().0
        NSWorkspace.shared.open(url)
    }
    
    @IBAction func chooseSavingPathAction(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.beginSheetModal(for: self.view.window!) { result in
            if result == .OK {
                let url = openPanel.url!
                defaults.lyricsCustomSavingPath = url
                self.userPathMenuItem.title = url.lastPathComponent
                self.userPathMenuItem.toolTip = url.path
                self.userPathMenuItem.isHidden = false
                self.savingPathPopUp.select(self.userPathMenuItem)
            } else {
                self.savingPathPopUp.selectItem(at: 0)
            }
        }
    }
    @IBAction func chooseLanguageAction(_ sender: NSPopUpButton) {
        let selectedIdx = sender.indexOfSelectedItem
        if selectedIdx == 0 {
            defaults.remove(.selectedLanguage)
            defaults.remove(.appleLanguages)
        } else {
            let lan = localizations[selectedIdx - 2]
            defaults[.selectedLanguage] = lan
            defaults[.appleLanguages] = [lan]
        }
    }
    
    @IBAction func helpTranslateAction(_ sender: NSButton) {
        NSWorkspace.shared.open(crowdinProjectURL)
    }
    
    @IBAction func preferredPlayerAction(_ sender: NSButton) {
        defaults[.preferredPlayerIndex] = sender.tag
        syncPreferredPlayerButtons()
        
        if sender.tag < 0 {
            autoLaunchButton.isEnabled = false
            autoLaunchButton.state = .off
            defaults[.launchAndQuitWithPlayer] = false
        } else {
            autoLaunchButton.isEnabled = true
        }
        
        if sender.tag == 1 || sender.tag == 3 || sender.tag == 4 {
            loadHomonymLrcButton.isEnabled = false
            loadHomonymLrcButton.state = .off
            defaults[.loadLyricsBesideTrack] = false
        } else {
            loadHomonymLrcButton.isEnabled = true
        }
    }

    private func installPreferredPlayerControls() {
        guard let container = preferAuto.superview else {
            return
        }
        container.subviews.forEach { $0.isHidden = true }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .equalSpacing
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let items: [(tag: Int, title: String, image: NSImage)] = [
            (-1, NSLocalizedString("Auto", comment: ""), NSImage(named: "now_playing_icon") ?? NSImage()),
            (0, NSLocalizedString("iTunes", comment: ""), MusicPlayerName.appleMusic.icon),
            (1, "Spotify", MusicPlayerName.spotify.icon),
            (5, NSLocalizedString("NetEase", comment: ""), MusicPlayerName.neteaseCloudMusic.icon),
            (2, "Vox", MusicPlayerName.vox.icon),
            (3, "Audirvana", MusicPlayerName.audirvana.icon),
            (4, "Swinsian", MusicPlayerName.swinsian.icon)
        ]

        preferredPlayerButtons = items.map { item in
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 3
            column.translatesAutoresizingMaskIntoConstraints = false

            let icon = NSButton()
            icon.image = item.image
            icon.imagePosition = .imageOnly
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.bezelStyle = .shadowlessSquare
            icon.isBordered = false
            icon.target = self
            icon.action = #selector(preferredPlayerIconAction(_:))
            icon.tag = item.tag
            icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 20).isActive = true

            let radio = NSButton(radioButtonWithTitle: item.title, target: self, action: #selector(preferredPlayerAction(_:)))
            radio.tag = item.tag
            radio.font = NSFont.systemFont(ofSize: 11)
            radio.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            column.addArrangedSubview(icon)
            column.addArrangedSubview(radio)
            stack.addArrangedSubview(column)
            return radio
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4)
        ])
    }

    @objc private func preferredPlayerIconAction(_ sender: NSButton) {
        defaults[.preferredPlayerIndex] = sender.tag
        syncPreferredPlayerButtons()
        preferredPlayerAction(sender)
    }

    private func syncPreferredPlayerButtons() {
        let selectedTag = defaults[.preferredPlayerIndex]
        preferredPlayerButtons.forEach { button in
            button.state = button.tag == selectedTag ? .on : .off
        }
    }
}

private let localizations = Bundle.main.localizations.filter { $0 != "Base" }.sorted()
