import SwiftUI

/// Cadran ±50 cents : bande colorée avec zone verte (tolérance « juste »),
/// aiguille, et trace des mesures qui naît à la pointe de l'aiguille puis remonte.
struct GaugeView: View {
    let trace: [TracePoint]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                draw(ctx, size: size, now: timeline.date.timeIntervalSinceReferenceDate - Dial.renderDelay)
            }
        }
        .accessibilityHidden(true)   // les valeurs sont lues dans le bloc texte sous le cadran
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, now: TimeInterval) {
        let g = DialGeometry(size: size)
        let tol = TunerModel.tolerance
        let state = NeedleState(trace: trace, now: now)

        // 1. Colonne verte : prolonge la zone juste au-dessus du cadran, là où monte la trace.
        let left = g.point(cents: -tol, r: g.tipRadius)
        let right = g.point(cents: tol, r: g.tipRadius)
        let column = CGRect(x: left.x, y: 0, width: right.x - left.x, height: left.y)
        ctx.fill(Path(column), with: .linearGradient(
            Gradient(colors: [.clear, dialColor(0, brightness: state.inTune ? 0.45 : 0.22)]),
            startPoint: CGPoint(x: column.midX, y: 0),
            endPoint: CGPoint(x: column.midX, y: column.maxY)))

        // 2. Bande colorée atténuée : vert, puis jaune, orange, rouge vers ±50 cents.
        let band = StrokeStyle(lineWidth: Dial.bandWidth, lineCap: .butt)
        for c in stride(from: -Dial.range, to: Dial.range, by: 1) {
            let segment = g.arc(from: c - 0.2, to: min(Dial.range, c + 1.2), r: g.radius)
            ctx.stroke(segment, with: .color(dialColor(c + 0.5, brightness: 0.42)), style: band)
        }

        // 3. Zone verte en pleine intensité, plus épaisse ; halo quand la corde est juste.
        let zone = g.arc(from: -tol, to: tol, r: g.radius)
        if state.inTune {
            ctx.stroke(zone, with: .color(dialColor(0, brightness: 0.25)), style: StrokeStyle(lineWidth: Dial.bandWidth + 16))
            ctx.stroke(zone, with: .color(dialColor(0, brightness: 0.5)), style: StrokeStyle(lineWidth: Dial.bandWidth + 9))
        }
        ctx.stroke(zone, with: .color(dialColor(0)), style: StrokeStyle(lineWidth: Dial.bandWidth + 4, lineCap: .butt))

        // 4. Graduations tous les 5 cents, repères à 0, ±25 et ±50.
        for i in stride(from: -50, through: 50, by: 5) {
            let major = i % 25 == 0
            let a = g.point(cents: Double(i), r: g.tickStart)
            let b = g.point(cents: Double(i), r: g.tickStart + (major ? Dial.majorTick : Dial.minorTick))
            let color: Color = i == 0 ? dialColor(0) : .white.opacity(major ? 0.75 : 0.35)
            ctx.stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: .color(color),
                       style: StrokeStyle(lineWidth: major ? 2 : 1.5, lineCap: .round))
        }
        for i in [-50, -25, 25, 50] {
            let label = i > 0 ? "+\(i)" : "−\(-i)"
            ctx.draw(Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.5)),
                     at: g.point(cents: Double(i), r: g.radius - 22))
        }
        ctx.draw(Text("♭").font(.title3).foregroundStyle(.white.opacity(0.6)),
                 at: g.point(degrees: -Dial.sweep - 9, r: g.radius))
        ctx.draw(Text("♯").font(.title3).foregroundStyle(.white.opacity(0.6)),
                 at: g.point(degrees: Dial.sweep + 9, r: g.radius))

        // 5. Trace : chaque mesure naît à la pointe de l'aiguille puis remonte.
        //    Fondu vers le haut par un masque ; halo large et sombre sous un trait fin.
        func position(_ cents: Double, age: Double) -> CGPoint {
            let p = g.point(cents: cents, r: g.tipRadius)
            return CGPoint(x: p.x, y: p.y - age * Dial.riseSpeed)
        }
        let lifetime = Double(g.pivot.y) / Dial.riseSpeed
        // Découpage en tronçons continus (coupés après un silence), du plus récent au plus ancien.
        typealias Node = (pt: CGPoint, cents: Double)
        var runs: [[Node]] = []
        var run: [Node] = state.attached ? [(position(state.cents, age: 0), state.cents)] : []
        var newerTime = now
        for point in trace[..<state.bornCount].reversed() {
            let age = now - point.time
            if age > lifetime { break }
            if newerTime - point.time >= Dial.maxGap, !run.isEmpty {
                runs.append(run)
                run = []
            }
            run.append((position(point.cents, age: age), point.cents))
            newerTime = point.time
        }
        if !run.isEmpty { runs.append(run) }
        // Lissage : courbes passant par les milieux, une couleur par morceau.
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var segments: [(path: Path, cents: Double)] = []
        for nodes in runs where nodes.count > 1 {
            for i in nodes.indices {
                let start = i == 0 ? nodes[i].pt : mid(nodes[i - 1].pt, nodes[i].pt)
                let end = i == nodes.count - 1 ? nodes[i].pt : mid(nodes[i].pt, nodes[i + 1].pt)
                var p = Path()
                p.move(to: start)
                p.addQuadCurve(to: end, control: nodes[i].pt)
                segments.append((p, nodes[i].cents))
            }
        }
        var traceCtx = ctx
        traceCtx.clipToLayer { mask in
            mask.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [.clear, .black]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: g.pivot.y - g.tipRadius)))
        }
        for s in segments {
            traceCtx.stroke(s.path, with: .color(dialColor(s.cents, brightness: 0.3)),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }
        for s in segments {
            traceCtx.stroke(s.path, with: .color(dialColor(s.cents)),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }

        // 6. Aiguille, couleur de la zone visée ; grise au repos.
        let tip = g.point(cents: state.cents, r: g.tipRadius)
        let needle = Path { $0.move(to: g.pivot); $0.addLine(to: tip) }
        let needleColor = state.active ? dialColor(state.cents) : Color.gray
        if state.inTune {
            ctx.stroke(needle, with: .color(dialColor(0, brightness: 0.35)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        }
        ctx.stroke(needle, with: .color(needleColor), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(needleColor))
        ctx.fill(Path(ellipseIn: CGRect(x: g.pivot.x - 8, y: g.pivot.y - 8, width: 16, height: 16)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: g.pivot.x - 3, y: g.pivot.y - 3, width: 6, height: 6)), with: .color(.black))
    }
}

// MARK: - Réglages et géométrie

/// Réglages du cadran.
private enum Dial {
    static let range = 50.0                 // échelle : ±50 cents
    static let sweep = 60.0                 // ±50 cents occupent ±60°
    static let bandWidth: CGFloat = 12
    static let tickInset: CGFloat = 10      // de l'axe de la bande au pied des graduations
    static let majorTick: CGFloat = 12
    static let minorTick: CGFloat = 6
    static let riseSpeed = 70.0             // pt/s : vitesse de remontée de la trace
    static let renderDelay = 0.06           // s : léger retard pour interpoler entre deux mesures (≈ 23/s)
    static let holdTime = 1.2               // s : silence avant le retour de l'aiguille au centre
    static let returnTime = 0.3             // s : durée de ce retour
    static let maxGap = 0.25                // s : au-delà, la trace est interrompue
}

/// Couleur d'une valeur en cents : vert dans la tolérance, puis jaune, orange, rouge vers ±50.
private func dialColor(_ cents: Double, brightness: Double = 0.9) -> Color {
    let m = abs(cents)
    guard m > TunerModel.tolerance else {
        return Color(hue: 0.375, saturation: 0.75, brightness: brightness)
    }
    let t = min(1, (m - TunerModel.tolerance) / (Dial.range - TunerModel.tolerance))
    return Color(hue: 0.24 - 0.22 * t.squareRoot(), saturation: 0.85, brightness: brightness)
}

/// Repère du cadran : pivot en bas, 0 cent à la verticale.
private struct DialGeometry {
    let pivot: CGPoint
    let radius: CGFloat                                     // axe de la bande colorée

    var tickStart: CGFloat { radius + Dial.tickInset }
    var tipRadius: CGFloat { tickStart + Dial.majorTick }   // pointe de l'aiguille, naissance de la trace

    init(size: CGSize) {
        pivot = CGPoint(x: size.width / 2, y: size.height - 18)
        let extra = Dial.tickInset + Dial.majorTick
        let byWidth = (size.width / 2 - 8) / CGFloat(sin(Dial.sweep * .pi / 180)) - extra
        let byHeight = pivot.y - 110 - extra                // garder au moins 110 pt pour la trace
        radius = max(60, min(150, byWidth, byHeight))
    }

    func point(degrees: Double, r: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: pivot.x + r * CGFloat(sin(a)), y: pivot.y - r * CGFloat(cos(a)))
    }

    func point(cents: Double, r: CGFloat) -> CGPoint {
        point(degrees: max(-Dial.range, min(Dial.range, cents)) / Dial.range * Dial.sweep, r: r)
    }

    /// Arc entre deux valeurs en cents, échantillonné tous les demi-cents.
    func arc(from c0: Double, to c1: Double, r: CGFloat) -> Path {
        Path { p in
            let steps = max(2, Int(abs(c1 - c0) * 2))
            for i in 0...steps {
                let pt = point(cents: c0 + (c1 - c0) * Double(i) / Double(steps), r: r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }
}

/// État de l'aiguille à l'instant affiché, déduit de la trace.
private struct NeedleState {
    var cents = 0.0
    var active = false      // son perçu récemment
    var attached = false    // la trace est reliée à la pointe
    var bornCount = 0       // mesures déjà apparues à l'instant affiché

    var inTune: Bool { active && abs(cents) <= TunerModel.tolerance }

    init(trace: [TracePoint], now: TimeInterval) {
        guard let i = trace.lastIndex(where: { $0.time <= now }) else { return }
        bornCount = i + 1
        let last = trace[i]
        cents = last.cents
        // Interpolation vers la mesure suivante : mouvement fluide entre deux analyses.
        if i + 1 < trace.count {
            let next = trace[i + 1]
            let span = next.time - last.time
            if span > 0, span < Dial.maxGap {
                cents += (next.cents - last.cents) * (now - last.time) / span
            }
        }
        let silence = now - last.time
        attached = silence < Dial.maxGap
        active = silence < Dial.holdTime
        if !active {
            cents *= max(0, 1 - (silence - Dial.holdTime) / Dial.returnTime)
        }
    }
}

#Preview {
    GaugeView(trace: [])
        .frame(height: 420)
        .background(.black)
}
