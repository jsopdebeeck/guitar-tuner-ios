import Foundation

/// Corde de guitare définie par sa note MIDI (E2 = 40, A4 = 69).
nonisolated struct GuitarString: Hashable, Sendable {
    let midi: Int

    var name: String { Note.name(midi, withOctave: false) }

    func frequency(a4: Double) -> Double {
        a4 * pow(2, Double(midi - 69) / 12)
    }
}

/// Accordage : cordes de la plus grave (6e) à la plus aiguë (1re).
nonisolated struct Tuning: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let strings: [GuitarString]

    init(_ name: String, _ midis: [Int]) {
        self.id = name
        self.name = name
        self.strings = midis.map(GuitarString.init(midi:))
    }

    static let all: [Tuning] = [
        Tuning("Standard (EADGBE)", [40, 45, 50, 55, 59, 64]),
        Tuning("Drop D (DADGBE)",   [38, 45, 50, 55, 59, 64]),
        Tuning("DADGAD",            [38, 45, 50, 55, 57, 62]),
        Tuning("Open D (DADF#AD)",  [38, 45, 50, 54, 57, 62]),
        Tuning("Open G (DGDGBD)",   [38, 43, 50, 55, 59, 62]),
    ]
}

nonisolated enum Note {
    static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    static func name(_ midi: Int, withOctave: Bool = true) -> String {
        let n = names[((midi % 12) + 12) % 12]
        return withOctave ? "\(n)\(midi / 12 - 1)" : n
    }
}
