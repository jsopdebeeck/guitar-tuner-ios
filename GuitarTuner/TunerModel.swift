import SwiftUI
import AVFoundation

/// Mesure horodatée, pour la trace qui remonte depuis l'aiguille.
nonisolated struct TracePoint: Sendable {
    let time: TimeInterval   // Date.timeIntervalSinceReferenceDate
    let cents: Double
}

@MainActor
@Observable
final class TunerModel {
    var tuning: Tuning = Tuning.all[0] {
        didSet { selectedString = nil; targetIndex = nil; history.removeAll(); trace.removeAll() }
    }
    var a4: Double = 440
    var isAuto = true {
        didSet { if isAuto { selectedString = nil } }
    }
    var errorMessage: String?

    private(set) var selectedString: Int?
    private(set) var targetIndex: Int?
    private(set) var frequency: Double?
    private(set) var cents: Double = 0
    private(set) var detectedNote = "–"

    /// Tolérance « juste », en cents : largeur de la zone verte du cadran.
    nonisolated static let tolerance = 3.0

    var isInTune: Bool { frequency != nil && abs(cents) <= Self.tolerance }

    /// Mesures des dernières secondes, affichées en trace sur le cadran.
    private(set) var trace: [TracePoint] = []

    var displayName: String {
        (targetIndex ?? selectedString).map { tuning.strings[$0].name } ?? "–"
    }

    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var history: [Double] = []
    @ObservationIgnored private var lastHeard = Date.distantPast

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access denied. Settings › Privacy & Security › Microphone."
            return
        }
        if capture == nil {
            capture = AudioCapture { [weak self] f in
                guard let self else { return }
                Task { @MainActor in self.handle(f) }
            }
        }
        do { try capture?.start() } catch { errorMessage = error.localizedDescription }
    }

    func stop() {
        capture?.stop()
    }

    func select(_ index: Int) {
        isAuto = false
        selectedString = index
        targetIndex = index
        trace.removeAll()
    }

    private func handle(_ f: Double?) {
        guard let f else {
            if Date().timeIntervalSince(lastHeard) > 1.2 {
                frequency = nil
                history.removeAll()
                if isAuto { targetIndex = nil }
            }
            return
        }
        lastHeard = Date()

        // Médiane glissante sur 5 mesures : élimine les sauts d'octave isolés.
        history.append(f)
        if history.count > 5 { history.removeFirst() }
        let median = history.sorted()[history.count / 2]

        frequency = median
        detectedNote = Note.name(Int((69 + 12 * log2(median / a4)).rounded()))

        let idx = isAuto ? nearestString(to: median) : (selectedString ?? nearestString(to: median))
        targetIndex = idx
        cents = 1200 * log2(median / tuning.strings[idx].frequency(a4: a4))

        let now = Date.timeIntervalSinceReferenceDate
        trace.append(TracePoint(time: now, cents: cents))
        trace.removeAll { now - $0.time > 6 }
    }

    private func nearestString(to f: Double) -> Int {
        tuning.strings.indices.min {
            abs(log2(f / tuning.strings[$0].frequency(a4: a4))) <
            abs(log2(f / tuning.strings[$1].frequency(a4: a4)))
        } ?? 0
    }
}
