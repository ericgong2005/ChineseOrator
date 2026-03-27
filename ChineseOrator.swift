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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let voice = selectedReadoutVoice() else {
            NSSound.beep()
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.volume = 1.0
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = true

        synthesizer.speak(utterance)
    }

    private func selectedReadoutVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let currentLanguageCode = AVSpeechSynthesisVoice.currentLanguageCode().lowercased()

        if currentLanguageCode.hasPrefix("zh"), !currentLanguageCode.hasPrefix("yue") {
            if let exact = voices.first(where: {
                $0.language.lowercased() == currentLanguageCode && isMandarinVoice($0)
            }) {
                return exact
            }
        }

        if let mandarinPremium = voices.first(where: {
            isMandarinVoice($0) && $0.quality == .premium
        }) {
            return mandarinPremium
        }

        if let mandarinEnhanced = voices.first(where: {
            isMandarinVoice($0) && $0.quality == .enhanced
        }) {
            return mandarinEnhanced
        }

        if let anyMandarin = voices.first(where: { isMandarinVoice($0) }) {
            return anyMandarin
        }

        return voices.first(where: {
            isYueVoice($0) && $0.quality == .premium
        })
    }

    private func isMandarinVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let language = voice.language.lowercased()
        return language == "zh-cn"
            || language == "zh-sg"
            || language == "cmn-cn"
            || language == "cmn-hans-cn"
            || language == "zh-hans"
            || (language.hasPrefix("zh") && !language.hasPrefix("yue"))
    }

    private func isYueVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.language.lowercased().hasPrefix("yue")
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