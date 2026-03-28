import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, AVSpeechSynthesizerDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private let synthesizer = AVSpeechSynthesizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        synthesizer.delegate = self
        requestAccessibility()
        registerHotKey()
    }

    private func requestAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func registerHotKey() {
        let eventHotKeyID = EventHotKeyID(signature: OSType(0x50494E59), id: 1)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_O),
            UInt32(controlKey | optionKey | cmdKey),
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()

                var hotKey = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKey
                )

                if status == noErr && hotKey.id == 1 {
                    delegate.handleHotkey()
                }

                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            nil
        )
    }

    private func handleHotkey() {
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }

            self.simulateCommandC()

            self.waitForClipboardChange(
                originalChangeCount: oldChangeCount,
                timeout: 0.75,
                interval: 0.03
            ) { [weak self] changed in
                guard let self else { return }
                guard changed else {
                    NSSound.beep()
                    return
                }

                let copiedText = pasteboard.string(forType: .string) ?? ""
                let normalized = copiedText.replacingOccurrences(of: "\r\n", with: "\n")
                let cleaned = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !cleaned.isEmpty else {
                    NSSound.beep()
                    return
                }

                self.readChineseText(cleaned)
            }
        }
    }

    private func readChineseText(_ text: String) {
        let phrases = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !phrases.isEmpty else {
            NSSound.beep()
            return
        }

        guard let yueVoice = yueReadoutVoice(),
              let shashaVoice = shashaReadoutVoice() else {
            NSSound.beep()
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        for phrase in phrases {
            let characterCount = countNonWhitespaceCharacters(in: phrase)

            let utterance: AVSpeechUtterance
            if characterCount >= 4 {
                utterance = AVSpeechUtterance(string: phrase)
                utterance.voice = yueVoice
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            } else {
                let shashaText = dottedTextForShasha(from: phrase)
                guard !shashaText.isEmpty else { continue }
                utterance = AVSpeechUtterance(string: shashaText)
                utterance.voice = shashaVoice
                utterance.rate = 0.0
            }

            utterance.volume = 1.0
            utterance.prefersAssistiveTechnologySettings = false
            synthesizer.speak(utterance)
        }
    }

    private func countNonWhitespaceCharacters(in text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    private func dottedTextForShasha(from phrase: String) -> String {
        let stripped = stripPunctuation(from: phrase)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stripped.isEmpty else { return "" }

        let chars = stripped.filter { !$0.isWhitespace }.map { String($0) }
        return chars.joined(separator: "")
    }

    private func stripPunctuation(from text: String) -> String {
        let punctuationAndSymbols = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.controlCharacters)
            .union(CharacterSet(charactersIn: "，。！？；：、“”‘’（）〔〕【】《》〈〉「」『』—…·、　"))

        let scalars = text.unicodeScalars.map { scalar -> String in
            punctuationAndSymbols.contains(scalar) ? "" : String(scalar)
        }

        return scalars.joined()
    }

    private func yueReadoutVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        if let exact = voices.first(where: { $0.name.caseInsensitiveCompare("Yue") == .orderedSame }) {
            return exact
        }

        if let contains = voices.first(where: { $0.name.range(of: "Yue", options: .caseInsensitive) != nil }) {
            return contains
        }

        return voices.first(where: { $0.language.lowercased().hasPrefix("yue") })
    }

    private func shashaReadoutVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        if let exact = voices.first(where: { $0.name.caseInsensitiveCompare("ShaSha") == .orderedSame }) {
            return exact
        }

        if let contains = voices.first(where: { $0.name.range(of: "ShaSha", options: .caseInsensitive) != nil }) {
            return contains
        }

        return voices.first(where: { $0.name.range(of: "shasha", options: .caseInsensitive) != nil })
    }

    private func waitForClipboardChange(
        originalChangeCount: Int,
        timeout: TimeInterval,
        interval: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        let deadline = Date().addingTimeInterval(timeout)

        func check() {
            if pasteboard.changeCount != originalChangeCount {
                completion(true)
                return
            }

            if Date() >= deadline {
                completion(false)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                check()
            }
        }

        check()
    }

    private func simulateCommandC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: false
        )

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()