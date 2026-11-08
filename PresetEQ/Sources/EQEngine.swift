import AVFoundation
import Foundation

final class EQEngine: ObservableObject {
    static let maxBands = 32
    static let flat10: [Band] = ([31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000] as [Float])
        .map { Band(freq: $0, q: 1.41) }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: EQEngine.maxBands)
    private var file: AVAudioFile?
    private var generation = 0

    @Published var bands: [Band] = EQEngine.flat10 { didSet { applyEQ() } }
    @Published var preamp: Float = 0 { didSet { applyEQ() } }
    @Published var eqEnabled = true { didSet { applyEQ() } }
    @Published var isPlaying = false
    @Published var trackName = "No track loaded"
    @Published var presets: [Preset] = []
    @Published var activePreset = "Flat"
    @Published var message: String?

    private var presetsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("presets.json")
    }

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.attach(player)
        engine.attach(eq)
        if let d = try? Data(contentsOf: presetsURL),
           let p = try? JSONDecoder().decode([Preset].self, from: d) { presets = p }
        applyEQ()
    }

    // MARK: EQ
    static func bandwidth(fromQ q: Float) -> Float {
        let q = max(q, 0.05)
        let bw = 2 * asinh(1 / (2 * q)) / Float(M_LN2)
        return min(5, max(0.05, bw))
    }

    private func applyEQ() {
        eq.bypass = !eqEnabled
        eq.globalGain = min(24, max(-96, preamp))
        for (i, b) in eq.bands.enumerated() {
            if i < bands.count {
                let s = bands[i]
                b.filterType = s.type.au
                b.frequency = min(20000, max(20, s.freq))
                b.gain = min(24, max(-96, s.gain))
                b.bandwidth = Self.bandwidth(fromQ: s.q)
                b.bypass = !s.enabled
            } else {
                b.bypass = true
            }
        }
    }

    // MARK: Playback
    func loadTrack(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tracks", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            let f = try AVAudioFile(forReading: dest)

            generation += 1
            player.stop()
            engine.stop()
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(eq)
            engine.connect(player, to: eq, format: f.processingFormat)
            engine.connect(eq, to: engine.mainMixerNode, format: f.processingFormat)
            file = f
            trackName = url.deletingPathExtension().lastPathComponent
            isPlaying = false
            applyEQ()
            try engine.start()
            schedule()
        } catch {
            message = "Could not open track: \(error.localizedDescription)"
        }
    }

    private func schedule() {
        guard let file else { return }
        file.framePosition = 0
        generation += 1
        let g = generation
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, g == self.generation else { return }
                self.player.stop()
                self.isPlaying = false
                self.schedule()
            }
        }
    }

    func togglePlay() {
        guard file != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if !engine.isRunning { try? engine.start() }
            player.play()
            isPlaying = true
        }
    }

    // MARK: Presets
    func apply(_ p: Preset) {
        bands = Array(p.bands.prefix(Self.maxBands))
        preamp = p.preamp
        activePreset = p.name
    }

    func resetFlat() {
        bands = Self.flat10
        preamp = 0
        activePreset = "Flat"
    }

    func saveCurrent(as name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        store(Preset(name: n, preamp: preamp, bands: bands))
        activePreset = n
    }

    private func store(_ p: Preset) {
        if let i = presets.firstIndex(where: { $0.name == p.name }) { presets[i] = p } else { presets.append(p) }
        persist()
    }

    func deletePresets(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(presets) { try? d.write(to: presetsURL) }
    }

    // MARK: Import (audio file, EasyEffects .json, AutoEQ .txt)
    func handleImport(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "json" || ext == "txt" {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { message = "Could not read preset file."; return }
            let name = url.deletingPathExtension().lastPathComponent
            let p = ext == "json"
                ? PresetParser.easyEffects(data, name: name)
                : PresetParser.autoEQ(String(decoding: data, as: UTF8.self), name: name)
            if let p {
                store(p)
                apply(p)
            } else {
                message = "No equalizer bands found in that file."
            }
        } else {
            loadTrack(url)
        }
    }
}
