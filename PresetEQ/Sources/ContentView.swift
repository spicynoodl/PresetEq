import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var eng = EQEngine()
    @State private var showImporter = false
    @State private var showSave = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Now playing") {
                    Text(eng.trackName)
                    HStack {
                        Button("Open track") { showImporter = true }
                        Spacer()
                        Button(eng.isPlaying ? "Pause" : "Play") { eng.togglePlay() }
                    }
                    .buttonStyle(.borderless)
                    Toggle("Equalizer on", isOn: $eng.eqEnabled)
                }

                Section("Presets (active: \(eng.activePreset))") {
                    Button("Import preset (.json / .txt)") { showImporter = true }
                    Button("Save current as…") { newName = ""; showSave = true }
                    Button("Reset to flat") { eng.resetFlat() }
                    ForEach(eng.presets) { p in
                        Button(p.name) { eng.apply(p) }
                    }
                    .onDelete { eng.deletePresets(at: $0) }
                }
                .buttonStyle(.borderless)

                Section("Preamp") {
                    HStack {
                        Slider(value: $eng.preamp, in: -24...12)
                        Text(String(format: "%+.1f dB", eng.preamp)).monospacedDigit()
                    }
                }

                Section("Bands") {
                    ForEach($eng.bands) { $b in BandRow(band: $b) }
                        .onDelete { eng.bands.remove(atOffsets: $0) }
                    if eng.bands.count < EQEngine.maxBands {
                        Button("Add band") { eng.bands.append(Band()) }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("PresetEQ")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio, .json, .plainText]) { result in
            if case .success(let url) = result { eng.handleImport(url) }
        }
        .alert("Save preset", isPresented: $showSave) {
            TextField("Name", text: $newName)
            Button("Save") { eng.saveCurrent(as: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("PresetEQ",
               isPresented: Binding(get: { eng.message != nil },
                                    set: { if !$0 { eng.message = nil } })) {
            Button("OK") {}
        } message: { Text(eng.message ?? "") }
    }
}

struct BandRow: View {
    @Binding var band: Band

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Int(band.freq)) Hz").bold()
                Text(band.type.label).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%+.1f dB", band.gain)).monospacedDigit()
                Toggle("", isOn: $band.enabled).labelsHidden()
            }
            Slider(value: $band.gain, in: -24...24)
            HStack {
                Text("Hz").font(.caption)
                Slider(value: Binding(get: { log10(band.freq) },
                                      set: { band.freq = pow(10, $0) }),
                       in: log10(Float(20))...log10(Float(20000)))
            }
            HStack {
                Text("Q").font(.caption)
                Slider(value: $band.q, in: 0.1...10)
                Text(String(format: "%.2f", band.q)).font(.caption).monospacedDigit()
            }
        }
    }
}
