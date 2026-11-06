import AVFoundation
import Accelerate

// MARK: - YIN (de Cheveigné & Kawahara, 2002)

/// Détecteur de fréquence fondamentale YIN, vectorisé avec vDSP.
nonisolated struct YIN: Sendable {
    let sampleRate: Double
    var minFrequency: Double = 60     // sous le D2 (73,4 Hz) des accordages "drop"
    var maxFrequency: Double = 1200
    var threshold: Float = 0.12

    /// Renvoie la fréquence en Hz, ou nil si aucune périodicité fiable.
    func detect(_ x: [Float]) -> Double? {
        let n = x.count
        let tauMax = min(Int(sampleRate / minFrequency), n / 2)
        let tauMin = max(2, Int(sampleRate / maxFrequency))
        let w = n - tauMax
        guard tauMax > tauMin + 2, w > 0 else { return nil }

        // 1. Fonction de différence d(τ)
        var d = [Float](repeating: 0, count: tauMax + 1)
        var diff = [Float](repeating: 0, count: w)
        x.withUnsafeBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for tau in 1...tauMax {
                vDSP_vsub(base, 1, base + tau, 1, &diff, 1, vDSP_Length(w))
                var s: Float = 0
                vDSP_svesq(diff, 1, &s, vDSP_Length(w))
                d[tau] = s
            }
        }

        // 2. Différence moyenne normalisée cumulée
        var cmnd = [Float](repeating: 1, count: tauMax + 1)
        var running: Float = 0
        for tau in 1...tauMax {
            running += d[tau]
            cmnd[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
        }

        // 3. Seuil absolu + descente jusqu'au minimum local
        var tau = tauMin
        var estimate = -1
        while tau < tauMax {
            if cmnd[tau] < threshold {
                while tau + 1 < tauMax, cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                estimate = tau
                break
            }
            tau += 1
        }
        guard estimate > 0 else { return nil }

        // 4. Interpolation parabolique
        let s0 = cmnd[estimate - 1], s1 = cmnd[estimate], s2 = cmnd[estimate + 1]
        let denom = s0 + s2 - 2 * s1
        let shift = denom != 0 ? 0.5 * (s0 - s2) / denom : 0
        let period = Double(estimate) + Double(shift)
        let f = sampleRate / period
        return (minFrequency...maxFrequency).contains(f) ? f : nil
    }
}

// MARK: - Capture micro

enum AudioCaptureError: LocalizedError {
    case noInput
    var errorDescription: String? { "No microphone input available." }
}

/// Capture micro via AVAudioEngine ; analyse sur une file série dédiée.
nonisolated final class AudioCapture: @unchecked Sendable {
    typealias Handler = @Sendable (_ frequency: Double?) -> Void

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "tuner.dsp", qos: .userInteractive)
    private let windowSize = 4096     // ≈ 85 ms à 48 kHz : couvre ~6 périodes de E2
    private let hopSize = 2048        // ≈ 23 analyses/s
    private let rmsGate: Float = 0.005
    private var pending: [Float] = []
    private let handler: Handler
    private(set) var isRunning = false

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        // .measurement désactive AGC et traitements vocaux : signal brut, indispensable pour un accordeur.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.noInput }

        let detector = YIN(sampleRate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async { self.process(samples, detector) }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        queue.async { self.pending.removeAll() }
        isRunning = false
    }

    private func process(_ samples: [Float], _ detector: YIN) {
        pending.append(contentsOf: samples)
        while pending.count >= windowSize {
            let window = Array(pending.prefix(windowSize))
            pending.removeFirst(hopSize)

            var rms: Float = 0
            vDSP_rmsqv(window, 1, &rms, vDSP_Length(windowSize))
            handler(rms > rmsGate ? detector.detect(window) : nil)
        }
    }
}
