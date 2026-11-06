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
/// Le pilotage du moteur et de la session audio (start, stop, reprise) passe par une
/// seconde file série, `control` : `AVAudioSession.setActive` peut bloquer, il ne doit
/// pas tourner sur le fil principal. L'état du moteur n'est lu et modifié que sur `control`.
nonisolated final class AudioCapture: @unchecked Sendable {
    typealias Handler = @Sendable (_ frequency: Double?) -> Void

    private var engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "tuner.dsp", qos: .userInteractive)
    private let control = DispatchQueue(label: "tuner.audio.control", qos: .userInitiated)
    private let windowSize = 4096     // ≈ 85 ms à 48 kHz : couvre ~6 périodes de E2
    private let hopSize = 2048        // ≈ 23 analyses/s
    private let rmsGate: Float = 0.005
    private var pending: [Float] = []
    private let handler: Handler
    private var tapInstalled = false
    private var wantsRunning = false  // capture demandée par l'app (au premier plan)
    private var observers: [NSObjectProtocol] = []

    init(handler: @escaping Handler) {
        self.handler = handler
        observeSystemEvents()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Démarre la capture hors du fil principal et rend la main une fois le moteur lancé.
    /// Sans effet si le moteur tourne déjà ; relance un moteur arrêté par le système.
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            control.async {
                do {
                    try self.startEngine()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Arrête la capture et libère la session audio, hors du fil principal.
    func stop() {
        control.async { self.stopEngine() }
    }

    // MARK: Pilotage, sur la file `control` uniquement

    private func startEngine() throws {
        dispatchPrecondition(condition: .onQueue(control))
        wantsRunning = true
        guard !engine.isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        // .measurement désactive AGC et traitements vocaux : signal brut, indispensable pour un accordeur.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.noInput }

        // Un tap peut rester posé après un arrêt imposé par le système, et le format a pu changer :
        // on le remplace.
        if tapInstalled { input.removeTap(onBus: 0) }
        let detector = YIN(sampleRate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async { self.process(samples, detector) }
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
    }

    private func stopEngine() {
        dispatchPrecondition(condition: .onQueue(control))
        wantsRunning = false
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        queue.async { self.pending.removeAll() }
    }

    /// Relance complète si la capture est demandée. Une erreur est ignorée ici :
    /// le retour de l'app au premier plan refait une tentative.
    private func resume() {
        dispatchPrecondition(condition: .onQueue(control))
        guard wantsRunning else { return }
        engine.stop()
        queue.async { self.pending.removeAll() }
        try? startEngine()
    }

    /// Les notifications arrivent sur le fil qui les poste ; tout le traitement repart sur `control`.
    private func observeSystemEvents() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers = [
            // Fin d'interruption (appel, Siri, alarme) : le moteur reste arrêté tant qu'on ne le relance pas.
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended,
                      let self else { return }
                self.control.async { self.resume() }
            },
            // Changement de configuration (micro branché ou retiré, fréquence d'échantillonnage) :
            // le moteur s'arrête de lui-même.
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] note in
                guard let self, let source = note.object as? AVAudioEngine else { return }
                self.control.async {
                    guard source === self.engine else { return }
                    self.resume()
                }
            },
            // Réinitialisation des services audio : les objets audio existants ne sont plus valides,
            // il faut un moteur neuf.
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.control.async {
                    self.engine = AVAudioEngine()
                    self.tapInstalled = false
                    self.resume()
                }
            },
        ]
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
