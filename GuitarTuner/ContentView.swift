import SwiftUI

struct ContentView: View {
    @State private var model = TunerModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 12) {
            header
            GaugeView(trace: model.trace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(model.displayName)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundStyle(model.isInTune ? .green : .primary)
            readout
            stringRow
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: model.isInTune) { _, new in new }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.start() }
            case .background: model.stop()
            default: break
            }
        }
        .alert("Microphone",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            Menu {
                Picker("Tuning", selection: $model.tuning) {
                    ForEach(Tuning.all) { Text($0.name).tag($0) }
                }
                Picker("Reference pitch", selection: $model.a4) {
                    ForEach([432.0, 438, 440, 442], id: \.self) {
                        Text("A4 = \(Int($0)) Hz").tag($0)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.tuning.name).font(.headline)
                    Text("A4 = \(Int(model.a4)) Hz").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Auto", isOn: $model.isAuto)
                .fixedSize()
                .tint(.green)
        }
    }

    private var readout: some View {
        VStack(spacing: 6) {
            if let f = model.frequency {
                HStack(spacing: 16) {
                    Text("\(f.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))) Hz")
                    Text(model.detectedNote)
                    Text("\(model.cents >= 0 ? "+" : "")\(Int(model.cents.rounded())) ¢")
                }
                Text(model.isInTune ? "In tune" : (model.cents < 0 ? "↑ Tune up" : "↓ Tune down"))
                    .foregroundStyle(model.isInTune ? .green : .orange)
            } else {
                Text(model.isAuto ? "Play a string" : "Play the \(model.displayName) string")
            }
        }
        .font(.title3.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(height: 60)
    }

    private var stringRow: some View {
        HStack(spacing: 10) {
            ForEach(Array(model.tuning.strings.enumerated()), id: \.offset) { i, s in
                let isTarget = model.targetIndex == i
                Button { model.select(i) } label: {
                    Text(s.name)
                        .font(.title3.bold())
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(
                            isTarget ? (model.isInTune ? Color.green : Color.accentColor)
                                     : Color.white.opacity(0.12)))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
