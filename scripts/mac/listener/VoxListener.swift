// VoxListener - macOS voice input for Vox. Wake word + dictation through
// Apple's on-device Speech framework; each finished command is handed to
// scripts/mac/send.sh, which types it into the target terminal.
//
// Built into ~/.claude/vox/VoxListener.app by build-listener.sh and started
// with `open`, so macOS asks for mic/speech permission on behalf of this app.
// Run as a child of the terminal instead, the terminal's own usage strings
// apply - Terminal.app has none, and macOS kills the process on first use.
//
//   VoxListener --plugin-root <dir>                 listen on the microphone
//   VoxListener --plugin-root <dir> --hub           multi-CLI hub: "hey <name>" per named pane
//   VoxListener --plugin-root <dir> --file <audio>  same, fed from a file (testing)
//   add --debug to log every transcript
//   VoxListener --check                             write permission/engine report to check.txt

import AppKit
import AVFoundation
import CoreAudio
import Speech

let stateDir = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/vox"
let debug = CommandLine.arguments.contains("--debug")
let hubMode = CommandLine.arguments.contains("--hub")
let pidPath = stateDir + (hubMode ? "/hub.pid" : "/listener.pid")
let namesPath = stateDir + "/names.json"

func log(_ message: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) [listener] \(message)\n"
    let path = stateDir + "/voice.log"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        h.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

func beep(_ name: String) {
    NSSound(named: NSSound.Name(name))?.play()
}

// Defaults mirror scripts/common.ps1; config.json overrides any key.
struct Config {
    var wakeWords = ["hey claude", "okay claude"]
    var endWords = ["over", "send it", "go ahead", "that is all", "send"]
    var duplex = "half"
    var ttsTailMs = 300.0
    var silenceGapSec = 2.5
    var maxCommandSec = 30.0
    var commandWaitSec = 10.0
    var followUpSec = 8.0
    // Words dictation should prefer, e.g. "main" over "Maine", "rebase" over "re-base".
    var hintWords = ["main", "rebase", "merge", "PR", "pull request", "commit", "branch"]
    // Whole words to rewrite before typing, for mishearings hints don't fix.
    var corrections = ["Maine": "main"]

    static func load() -> Config {
        var c = Config()
        guard let data = FileManager.default.contents(atPath: stateDir + "/config.json"),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return c }
        if let v = j["wakeWords"] as? [String] { c.wakeWords = v }
        if let v = j["endWords"] as? [String] { c.endWords = v }
        if let v = j["duplex"] as? String { c.duplex = v }
        if let v = j["ttsTailMs"] as? Double { c.ttsTailMs = v }
        if let v = j["silenceGapSec"] as? Double { c.silenceGapSec = v }
        if let v = j["maxCommandSec"] as? Double { c.maxCommandSec = v }
        if let v = j["commandWaitSec"] as? Double { c.commandWaitSec = v }
        if let v = j["followUpSec"] as? Double { c.followUpSec = v }
        if let v = j["hintWords"] as? [String] { c.hintWords = v }
        if let v = j["corrections"] as? [String: String] { c.corrections = v }
        return c
    }
}

extension String {
    // Whole-word, case-insensitive replacements ("Maine" -> "main").
    func corrected(_ map: [String: String]) -> String {
        var s = self
        for (heard, want) in map {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: heard) + "\\b"
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                            withTemplate: NSRegularExpression.escapedTemplate(for: want))
        }
        return s
    }
}

func normalize(_ word: String) -> String {
    String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

// Dictation writes some words differently from how they're configured
// ("Claude" as "Claud", "okay" as "OK"); treat these as the same word.
let soundalikes: [String: Set<String>] = [
    "claude": ["cloud", "clyde", "claud", "clod", "claudes"],
    "okay": ["ok"],
]

func sameWord(_ heard: String, _ wanted: String) -> Bool {
    heard == wanted || soundalikes[wanted]?.contains(heard) == true
}

// Named panes for the hub: names.json maps name -> {kind, id, cwd, ...}
// (written by voice-name.sh). Returns (name, cwd) sorted by name.
func readNames() -> [(name: String, cwd: String)] {
    guard let data = FileManager.default.contents(atPath: namesPath),
          let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else { return [] }
    return j.map { ($0.key, $0.value["cwd"] as? String ?? "") }.sorted { $0.name < $1.name }
}

func modified(_ path: String) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
}

// Menu-bar icon while the hub runs (the Windows hub's tray icon): named
// CLIs, the log, and quit.
final class HubMenu: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        item.button?.title = "Vox"
    }

    func rebuild(_ names: [(name: String, cwd: String)]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = menu.addItem(withTitle: "Vox Hub", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(.separator())
        if names.isEmpty {
            menu.addItem(withTitle: "  (no named CLIs - run /vox:name <name>)", action: nil, keyEquivalent: "").isEnabled = false
        }
        for n in names {
            let folder = (n.cwd as NSString).lastPathComponent
            menu.addItem(withTitle: "  \(n.name)  -  \(folder)", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
        let logItem = menu.addItem(withTitle: "Open log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        let quit = menu.addItem(withTitle: "Quit Vox Hub", action: #selector(quitHub), keyEquivalent: "")
        quit.target = self
        item.menu = menu
    }

    @objc func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: stateDir + "/voice.log"))
    }

    @objc func quitHub() {
        log("hub stopped from the menu bar")
        exit(0)
    }
}

final class Listener {
    let cfg = Config.load()
    let sendScript: String
    let recognizer: SFSpeechRecognizer
    var engine = AVAudioEngine()
    private var engineObserver: NSObjectProtocol?
    // Wake phrase words, and the named pane it routes to (hub mode only).
    private var wakePhrases: [(words: [String], name: String?)] = []
    let endPhrases: [[String]]
    private var namesStamp: Date?
    private var menu: HubMenu?
    private var routeName: String?

    // The audio thread appends to whichever request is current.
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var lastAudio = Date()
    private var usingMic = false
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var taskStarted = Date()

    private var capturing = false
    private var wakeAt = Date()
    private var command = ""
    private var lastChange = Date()
    private var endWordAt: Date?
    private var sending = false
    private var paused = false
    private var followUp = false
    private var carried = ""
    private var committedText = ""
    private var replySpeaking = false
    private var resumeAt: Date?

    init(pluginRoot: String, recognizer: SFSpeechRecognizer) {
        sendScript = pluginRoot + "/scripts/mac/send.sh"
        self.recognizer = recognizer
        endPhrases = cfg.endWords.map { $0.split(separator: " ").map { normalize(String($0)) } }
        if hubMode {
            menu = HubMenu()
            loadNames()
        } else {
            wakePhrases = cfg.wakeWords.map { (phraseWords($0), nil) }
        }
    }

    func phraseWords(_ phrase: String) -> [String] {
        phrase.split(separator: " ").map { normalize(String($0)) }
    }

    // Hub: "hey <name>" / "okay <name>" for every named pane (as on Windows).
    func loadNames() {
        namesStamp = modified(namesPath)
        let names = readNames()
        wakePhrases = names.flatMap { n in ["hey", "okay"].map { (phraseWords("\($0) \(n.name)"), Optional(n.name)) } }
        menu?.rebuild(names)
        log(names.isEmpty ? "hub: no named CLIs yet - run /vox:name <name> in each Claude CLI"
                          : "hub: listening for \(names.map { "hey \($0.name)" }.joined(separator: ", "))")
    }

    var wakeStrings: [String] {
        wakePhrases.map { $0.words.joined(separator: " ") }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); lastAudio = Date(); request?.append(buffer); lock.unlock()
    }

    func startMicrophone() throws {
        usingMic = true
        // The engine's own change notice can miss a default-input switch;
        // CoreAudio reports those reliably.
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.restartMicrophone("switched to a new default input")
        }
        try startEngine()
    }

    // AVAudioEngine stops itself when the audio setup changes (a Bluetooth
    // speaker waking or reconnecting, a virtual device appearing, the default
    // input switching), and a restarted instance can stay bound to the old
    // device - so every (re)start builds a fresh engine.
    private func startEngine() throws {
        if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartMicrophone("changed (audio device switch)")
        }
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        lock.lock(); lastAudio = Date(); lock.unlock()
    }

    func restartMicrophone(_ why: String) {
        log("audio input \(why) - restarting it")
        do {
            try startEngine()
        } catch {
            // lastAudio stays stale, so the watchdog in tick() retries.
            log("audio input restart failed: \(error.localizedDescription)")
            return
        }
        capturing = false
        followUp = false
        if !paused && !sending { startTask() }
    }

    func run() {
        startTask()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    // A fresh recognition task. Also clears the transcript, so a wake word
    // heard earlier can't match again.
    func startTask() {
        // A new task starts with an empty transcript; mid-command, what was
        // already heard carries over so the command continues.
        carried = capturing ? command : ""
        committedText = ""
        if debug && capturing { log("new task mid-command, carrying '\(carried)'") }
        stopTask()
        generation += 1
        let gen = generation
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.addsPunctuation = true
        req.contextualStrings = wakeStrings + cfg.hintWords
        lock.lock(); request = req; lock.unlock()
        taskStarted = Date()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let result { self.handle(result) }
                if error != nil || result?.isFinal == true {
                    // Tasks end on their own after long silence; keep listening.
                    if !self.sending && !self.paused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if gen == self.generation { self.startTask() }
                        }
                    }
                }
            }
        }
    }

    func stopTask() {
        generation += 1
        lock.lock(); request?.endAudio(); request = nil; lock.unlock()
        task?.cancel()
        task = nil
    }

    // Index (into the transcript's words) just past the last wake phrase, if
    // any, and the named pane that phrase routes to.
    func wakeEnd(_ words: [String]) -> (end: Int, name: String?)? {
        var best: (end: Int, name: String?)?
        for phrase in wakePhrases where !phrase.words.isEmpty && words.count >= phrase.words.count {
            let n = phrase.words.count
            for i in 0...(words.count - n) where zip(words[i..<(i + n)], phrase.words).allSatisfy(sameWord) {
                if i + n > (best?.end ?? 0) { best = (i + n, phrase.name) }
            }
        }
        return best
    }

    // Words of the formatted transcript with their character ranges. Segments
    // aren't usable here: the recognizer returns a hinted phrase like
    // "Okay claude," as one segment, and punctuation as segments of its own.
    func words(_ s: NSString) -> [(word: String, range: NSRange)] {
        var out: [(String, NSRange)] = []
        s.enumerateSubstrings(in: NSRange(location: 0, length: s.length), options: .byWords) { w, r, _, _ in
            if let w { out.append((normalize(w), r)) }
        }
        return out
    }

    // The recognizer capitalizes each utterance; mid-sentence that reads
    // wrong ("list the files In the folder"). Lowercase an ordinary first
    // word, leaving "I" and acronyms alone.
    func continuation(_ s: String) -> String {
        let chars = Array(s)
        guard chars.count > 1, chars[0].isUppercase, chars[1].isLowercase else { return s }
        return chars[0].lowercased() + String(chars.dropFirst())
    }

    func handle(_ result: SFSpeechRecognitionResult) {
        if paused || sending { return }
        let s = result.bestTranscription.formattedString as NSString
        if (s as String) == committedText { return }
        if debug { log("heard: \(s) [final=\(result.isFinal) meta=\(result.speechRecognitionMetadata != nil)]") }
        let w = words(s)
        // While capturing (after a wake word in an earlier task, or in a
        // follow-up window) the whole utterance is command; a wake word said
        // here still marks where it starts.
        let wake = wakeEnd(w.map { $0.word })
        if wake == nil && !capturing { return }
        let end = wake?.end ?? 0
        // A wake word said mid-command re-routes it (hub: "hey nova" after all).
        if let wake, hubMode { routeName = wake.name }

        if !capturing {
            capturing = true
            wakeAt = Date()
            command = ""
            endWordAt = nil
            lastChange = Date()
            let first = w[max(0, end - 2)].range.location
            let heard = s.substring(with: NSRange(location: first, length: NSMaxRange(w[end - 1].range) - first))
            log("wake '\(heard)'" + (routeName.map { " -> \($0)" } ?? ""))
            beep("Tink")
            if cfg.duplex == "full" { hushSpeaker() }
        }

        var stop = s.length
        let spoken = w[end...].map { $0.word }
        var endHit = false
        for phrase in endPhrases where !phrase.isEmpty && spoken.count > phrase.count && Array(spoken.suffix(phrase.count)) == phrase {
            stop = w[w.count - phrase.count].range.location
            endHit = true
            break
        }
        // End words ("over", "send", "go ahead") are ordinary words too: only
        // the LAST thing said counts, so more speech after one cancels it.
        if endHit { endWordAt = endWordAt ?? Date() } else { endWordAt = nil }
        var cmd = ""
        if end < w.count, stop > w[end].range.location {
            let start = w[end].range.location
            let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:"))
            cmd = s.substring(with: NSRange(location: start, length: stop - start)).trimmingCharacters(in: edges)
        }
        // A wake word in this utterance starts the command over.
        let prefix = wake == nil ? carried : ""
        if !prefix.isEmpty { cmd = cmd.isEmpty ? prefix : prefix + " " + continuation(cmd) }
        if cmd != command {
            command = cmd
            lastChange = Date()
        }
        // At a pause the recognizer ends the utterance (metadata arrives) and
        // the same task starts a fresh transcript for the next one, e.g. after
        // "hey claude" or a think-pause mid-sentence. Keep what was said so far.
        if capturing && result.speechRecognitionMetadata != nil {
            carried = command
            committedText = s as String
        }
    }

    func tick() {
        if FileManager.default.fileExists(atPath: stateDir + "/stop.flag") {
            log("stop.flag seen - exiting")
            exit(0)
        }

        // Watchdog: a running engine delivers buffers continuously (silence
        // included), so a gap means the input died without a notification.
        if usingMic {
            lock.lock(); let gap = Date().timeIntervalSince(lastAudio); lock.unlock()
            if gap >= 3 {
                restartMicrophone("silent for \(Int(gap))s")
                return
            }
        }

        // Half duplex: go deaf while Claude speaks so the mic can't hear the
        // reply and wake itself.
        if cfg.duplex == "half" {
            if speakerAlive() {
                if !paused {
                    paused = true
                    capturing = false
                    followUp = false
                    stopTask()
                    log("TTS speaking - listener paused")
                }
                resumeAt = nil
                return
            }
            if paused {
                if resumeAt == nil { resumeAt = Date().addingTimeInterval(cfg.ttsTailMs / 1000) }
                if Date() < resumeAt! { return }
                paused = false
                resumeAt = nil
                startTask()
                log("TTS ended - listening resumed")
                startFollowUp()
                return
            }
        } else {
            // Full duplex keeps listening through the reply; still open a
            // follow-up window once it ends.
            if speakerAlive() {
                replySpeaking = true
            } else if replySpeaking {
                replySpeaking = false
                if !capturing && !sending {
                    startTask()
                    startFollowUp()
                }
            }
        }
        if sending { return }

        if capturing {
            let elapsed = Date().timeIntervalSince(wakeAt)
            if command.isEmpty && elapsed >= (followUp ? cfg.followUpSec : cfg.commandWaitSec) {
                if followUp {
                    log("follow-up window closed - say the wake word to continue")
                } else {
                    log("no speech in \(Int(cfg.commandWaitSec))s - reset, ready for next wake")
                    beep("Funk")
                }
                capturing = false
                followUp = false
                startTask()
            } else if let e = endWordAt, Date().timeIntervalSince(e) >= 1.0 {
                // Settle first: partial results lag, so give "…switch over to main"
                // time to show the words after "over" (which cancels it).
                log("end-word - finishing")
                finish()
            } else if !command.isEmpty && Date().timeIntervalSince(lastChange) >= cfg.silenceGapSec {
                finish()
            } else if elapsed >= cfg.maxCommandSec {
                log("command time cap reached")
                finish()
            }
        } else if hubMode && modified(namesPath) != namesStamp {
            // A pane was (re)named: new wake phrases take effect on a fresh task.
            loadNames()
            startTask()
        } else if Date().timeIntervalSince(taskStarted) >= 50 {
            // Keep the transcript short and stay clear of per-task time limits.
            startTask()
        }
    }

    // After a spoken reply, listen briefly without the wake word so a
    // follow-up flows like conversation. followUpSec 0 turns this off.
    func startFollowUp() {
        guard cfg.followUpSec > 0 else { return }
        if hubMode {
            // Follow up with whichever CLI's reply was spoken last.
            let last = (try? String(contentsOfFile: stateDir + "/last-spoken-name", encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !last.isEmpty, readNames().contains(where: { $0.name == last }) else { return }
            routeName = last
        }
        capturing = true
        followUp = true
        wakeAt = Date()
        command = ""
        endWordAt = nil
        lastChange = Date()
        beep("Tink")
        log("follow-up: listening \(Int(cfg.followUpSec))s without the wake word" + (routeName.map { " (-> \($0))" } ?? ""))
    }

    func finish() {
        capturing = false
        followUp = false
        endWordAt = nil
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines).corrected(cfg.corrections)
        command = ""
        stopTask()
        if text.isEmpty {
            log("empty command - ignored")
            beep("Funk")
            startTask()
            return
        }
        sending = true
        let args = [sendScript, text] + (hubMode ? [routeName ?? ""] : [])
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = args
            var ok = false
            do {
                try p.run()
                p.waitUntilExit()
                ok = p.terminationStatus == 0
            } catch {
                log("send failed to launch: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                beep(ok ? "Pop" : "Basso")
                self.sending = false
                self.startTask()
            }
        }
    }

    func speakerPid() -> pid_t? {
        guard let s = try? String(contentsOfFile: stateDir + "/speaker.pid", encoding: .utf8),
              let p = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return p
    }

    func speakerAlive() -> Bool {
        guard let p = speakerPid() else { return false }
        return kill(p, 0) == 0
    }

    func hushSpeaker() {
        if let p = speakerPid() { kill(p, SIGTERM) }
    }
}

// Feeds an audio file at real-time pace, then silence, so the wake/silence
// timing behaves as it would on the microphone.
final class FileFeeder {
    let listener: Listener
    let file: AVAudioFile
    let chunk: AVAudioFrameCount
    var silenceLeft = 40

    init(listener: Listener, path: String) throws {
        self.listener = listener
        file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
    }

    func start() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self, let buf = AVAudioPCMBuffer(pcmFormat: self.file.processingFormat, frameCapacity: self.chunk) else { return }
            if self.file.framePosition < self.file.length {
                try? self.file.read(into: buf, frameCount: self.chunk)
            } else {
                buf.frameLength = self.chunk // zero-filled silence
                self.silenceLeft -= 1
                if self.silenceLeft <= 0 {
                    t.invalidate()
                    log("file input finished")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
                }
            }
            self.listener.append(buf)
        }
    }
}

func requestSpeech(_ done: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
    SFSpeechRecognizer.requestAuthorization { s in DispatchQueue.main.async { done(s) } }
}

func requestMic(_ done: @escaping (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
}

func describe(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch s {
    case .authorized: return "ALLOWED"
    case .denied: return "DENIED"
    case .restricted: return "RESTRICTED"
    default: return "NOT DETERMINED"
    }
}

func runCheck() {
    requestSpeech { speech in
        requestMic { mic in
            var lines = ["Speech recognition: \(describe(speech))", "Microphone        : \(mic ? "ALLOWED" : "DENIED")"]
            var ok = speech == .authorized && mic
            if let r = SFSpeechRecognizer() {
                lines.append("Language          : \(r.locale.identifier)")
                lines.append("On-device model   : \(r.supportsOnDeviceRecognition ? "available" : "NOT available")")
                ok = ok && r.supportsOnDeviceRecognition
            } else {
                lines.append("Language          : no recognizer for \(Locale.current.identifier)")
                ok = false
            }
            lines.append(ok ? "RESULT: OK" : "RESULT: NOT READY")
            try? (lines.joined(separator: "\n") + "\n").write(toFile: stateDir + "/check.txt", atomically: true, encoding: .utf8)
            exit(0)
        }
    }
}

func runListener(pluginRoot: String, file: String?) {
    unlink(stateDir + "/stop.flag")
    requestSpeech { speech in
        requestMic { mic in
            guard speech == .authorized, mic || file != nil else {
                log("FATAL: permission missing (speech \(describe(speech)), mic \(mic ? "ALLOWED" : "DENIED")) - run /vox:check")
                exit(2)
            }
            guard let r = SFSpeechRecognizer(), r.supportsOnDeviceRecognition else {
                log("FATAL: no on-device speech model for \(Locale.current.identifier) - run /vox:check")
                exit(2)
            }
            let listener = Listener(pluginRoot: pluginRoot, recognizer: r)
            do {
                if let file {
                    let feeder = try FileFeeder(listener: listener, path: file)
                    feeder.start()
                    objc_setAssociatedObject(NSApp as Any, "feeder", feeder, .OBJC_ASSOCIATION_RETAIN)
                } else {
                    try listener.startMicrophone()
                }
            } catch {
                log("FATAL: audio input failed: \(error.localizedDescription)")
                exit(2)
            }
            objc_setAssociatedObject(NSApp as Any, "listener", listener, .OBJC_ASSOCIATION_RETAIN)
            try? "\(getpid())\n".write(toFile: pidPath, atomically: true, encoding: .utf8)
            atexit { unlink(pidPath) }
            listener.run()
            beep("Tink")
            let wake = hubMode ? "hey <name> (hub)" : listener.cfg.wakeWords.joined(separator: ", ")
            log("ready. engine=apple-speech (\(r.locale.identifier), on-device). wake: \(wake), duplex=\(listener.cfg.duplex)")
        }
    }
}

let args = CommandLine.arguments
func arg(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if args.contains("--check") {
    runCheck()
} else if let root = arg("--plugin-root") {
    runListener(pluginRoot: root, file: arg("--file"))
} else {
    log("FATAL: VoxListener needs --plugin-root or --check")
    exit(2)
}
app.run()
