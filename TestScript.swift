import Cocoa
import AVFoundation

// Compile with:
// swiftc Testscript.swift -o Testscript -framework Cocoa -framework AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, AVSpeechSynthesizerDelegate {
    private var window: NSWindow!
    private let synthesizer = AVSpeechSynthesizer()

    private let voiceLabel = NSTextField(labelWithString: "Voice:")
    private let voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let textLabel = NSTextField(labelWithString: "Text:")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()

    private let readButton = NSButton(title: "Read", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh Voices", target: nil, action: nil)

    private let statusLabel = NSTextField(labelWithString: "")

    private var availableVoices: [AVSpeechSynthesisVoice] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        synthesizer.delegate = self
        buildUI()
        loadVoices()
        setDefaultText()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildUI() {
        let windowRect = NSRect(x: 0, y: 0, width: 760, height: 500)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Chinese Voice Tester"

        guard let contentView = window.contentView else { return }

        [
            voiceLabel, voicePopup,
            textLabel, scrollView,
            readButton, stopButton, refreshButton,
            statusLabel
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        setupTextView()
        setupButtons()
        setupStatusLabel()

        NSLayoutConstraint.activate([
            voiceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            voiceLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),

            voicePopup.leadingAnchor.constraint(equalTo: voiceLabel.trailingAnchor, constant: 10),
            voicePopup.centerYAnchor.constraint(equalTo: voiceLabel.centerYAnchor),
            voicePopup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            textLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            textLabel.topAnchor.constraint(equalTo: voicePopup.bottomAnchor, constant: 18),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: readButton.topAnchor, constant: -12),

            readButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            readButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            readButton.widthAnchor.constraint(equalToConstant: 90),

            stopButton.leadingAnchor.constraint(equalTo: readButton.trailingAnchor, constant: 10),
            stopButton.bottomAnchor.constraint(equalTo: readButton.bottomAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 90),

            refreshButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            refreshButton.bottomAnchor.constraint(equalTo: readButton.bottomAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 130)
        ])
    }

    private func setupTextView() {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 16)

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
    }

    private func setupButtons() {
        readButton.target = self
        readButton.action = #selector(readText)

        stopButton.target = self
        stopButton.action = #selector(stopReading)

        refreshButton.target = self
        refreshButton.action = #selector(refreshVoices)
    }

    private func setupStatusLabel() {
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Ready"
    }

    private func setDefaultText() {
        textView.string = "你问我参加茶会的这几个小家伙？它们可是我忠实的追随者，咳，今天就破例为你介绍一下吧！这位是谢贝蕾妲小姐，最可爱的女仆，虽然有时会不小心剪坏我的衣服；这位是海薇玛夫人，可靠的管理人，将我的生活打理得井井有条；最后这位喜欢说教的是乌瑟勋爵，负责一切礼仪相关的事情。呵呵，虽然我已允许你参加我的茶会，但想要得到它们的认可，你还要多多努力才行！"
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:
            return "Premium"
        case .enhanced:
            return "Enhanced"
        default:
            return "Default"
        }
    }

    private func loadVoices() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        availableVoices = allVoices
            .filter { $0.language.hasPrefix("zh") }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                if lhs.language != rhs.language {
                    return lhs.language < rhs.language
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        voicePopup.removeAllItems()

        if availableVoices.isEmpty {
            voicePopup.addItem(withTitle: "No Chinese voices installed")
            statusLabel.stringValue = "No Chinese voices found"
            return
        }

        for voice in availableVoices {
            let title = "\(voice.name) [\(voice.language)] (\(qualityLabel(voice.quality)))"
            voicePopup.addItem(withTitle: title)
        }

        selectBestDefaultVoice()
        updateStatusForSelectedVoice()
    }

    private func selectBestDefaultVoice() {
        if let premiumIndex = availableVoices.firstIndex(where: { $0.quality == .premium && $0.language == "zh-CN" }) {
            voicePopup.selectItem(at: premiumIndex)
            return
        }

        if let enhancedIndex = availableVoices.firstIndex(where: { $0.quality == .enhanced && $0.language == "zh-CN" }) {
            voicePopup.selectItem(at: enhancedIndex)
            return
        }

        if let defaultCNIndex = availableVoices.firstIndex(where: { $0.language == "zh-CN" }) {
            voicePopup.selectItem(at: defaultCNIndex)
            return
        }

        voicePopup.selectItem(at: 0)
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        let index = voicePopup.indexOfSelectedItem
        guard index >= 0 && index < availableVoices.count else { return nil }
        return availableVoices[index]
    }

    private func updateStatusForSelectedVoice() {
        guard let voice = selectedVoice() else {
            statusLabel.stringValue = "No voice selected"
            return
        }

        statusLabel.stringValue = "Selected: \(voice.name) | \(voice.language) | \(qualityLabel(voice.quality)) | \(voice.identifier)"
    }

    @objc private func readText() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            statusLabel.stringValue = "Text box is empty"
            return
        }

        guard let voice = selectedVoice() else {
            NSSound.beep()
            statusLabel.stringValue = "No voice selected"
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice

        synthesizer.speak(utterance)
        updateStatusForSelectedVoice()
    }

    @objc private func stopReading() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            statusLabel.stringValue = "Stopped"
        }
    }

    @objc private func refreshVoices() {
        loadVoices()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        updateStatusForSelectedVoice()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        statusLabel.stringValue = "Finished"
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        statusLabel.stringValue = "Cancelled"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()