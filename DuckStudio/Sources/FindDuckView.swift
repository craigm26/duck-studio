import SwiftUI
import StudioKit

/// Find a real Microduck and complete its handshake.
///
/// THE ONLY SCREEN IN THIS APP THAT TOUCHES HARDWARE, and the only one nobody
/// here can test. Every UUID, byte layout and step order is transcribed from
/// `btd`'s source in `pollen-robotics/microduck`; none of it has met a robot,
/// because none of us has one until deliveries start. So the screen is built to
/// be useful to the FIRST PERSON WHO POINTS IT AT A DUCK: every step is named,
/// shown in order, and keeps its own failure, so "it didn't work" comes back as
/// "it failed at the version read, saying X" — which is a bug report somebody
/// can act on rather than a shrug.
struct FindDuckView: View {
    @StateObject private var scanner = DuckLinkScanner()

    var body: some View {
        List {
            if let radio = scanner.radio {
                Section {
                    Label(radio, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            Section {
                if scanner.found.isEmpty {
                    HStack(spacing: 10) {
                        if scanner.scanning { ProgressView() }
                        Text(scanner.scanning
                             ? "Listening for a duck…"
                             : "Not scanning.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(scanner.found) { duck in
                    Button { scanner.handshake(with: duck) } label: {
                        row(duck.sighting)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Ducks in range")
            } footer: {
                // WHY A SCAN IS WORTH HAVING ON ITS OWN. Pollen's `duckctl scan`
                // deliberately connects to nothing for this reason, and it is
                // the command they reach for when a robot is unreachable.
                Text("Scanning connects to nothing, so this works on a duck that is not answering anything else. The address comes out of the advertisement itself — which is the only way a listing can tell you where to ssh.")
            }

            if case .idle = scanner.progress {} else {
                Section("The handshake") {
                    ForEach(DuckLink.Step.allCases.filter { $0 != .scan }, id: \.self) { step in
                        stepRow(step)
                    }
                }
            }

            if case .done(let hello, let apiByte) = scanner.progress {
                Section {
                    LabeledContent("API version", value: "\(hello.apiVersion)")
                    if UInt32(apiByte) != hello.apiVersion {
                        // Two layers answered differently — see `apiByte`.
                        Label("The GATT read said \(apiByte) and hello said \(hello.apiVersion). "
                              + "Those come from different layers and should agree.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let daemon = hello.daemonVersion {
                        LabeledContent("Daemon", value: daemon)
                    }
                    LabeledContent("Revision") {
                        Text(hello.revision ?? "not from CI")
                            .font(.caption.monospaced())
                    }
                    Text(DuckLink.verdict(for: hello.apiVersion))
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("It answered")
                } footer: {
                    Text("A duck built on somebody's laptop reports no revision, and that is normal rather than a fault.")
                }
            }

            Section {
                Button {
                    scanner.begin()
                } label: {
                    Label(scanner.scanning ? "Scanning…" : "Scan for ducks",
                          systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(scanner.scanning)
                if scanner.scanning {
                    Button(role: .cancel) { scanner.stop() } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                }
            }

            Section {
                Text(DuckLink.whatThisCanDo)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Find a duck")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { scanner.stop() }
    }

    private func row(_ duck: DuckLink.Sighting) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(duck.name).font(.body)
                Text(address(duck.address))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if let rssi = duck.rssi {
                Text("\(rssi) dBm")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// The three cases `adv.rs` insists are different, kept different.
    private func address(_ address: DuckLink.Address) -> String {
        switch address {
        case .at(let ip): return ip
        case .none: return "no address — the duck has no wifi"
        case .notBroadcast: return "no address broadcast — an older release"
        }
    }

    private func stepRow(_ step: DuckLink.Step) -> some View {
        let state = state(of: step)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.tint)
                Text(step.title).font(.subheadline)
                Spacer()
                if state == .running { ProgressView() }
            }
            if state == .running || state == .failed {
                Text(step.detail).font(.caption2).foregroundStyle(.secondary)
            }
            if case .failed(let failed, let why) = scanner.progress, failed == step {
                Text(why).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private enum StepState: Equatable {
        case waiting, running, done, failed
        var symbol: String {
            switch self {
            case .waiting: return "circle"
            case .running: return "circle.dotted"
            case .done: return "checkmark.circle.fill"
            case .failed: return "xmark.octagon.fill"
            }
        }
        var tint: Color {
            switch self {
            case .waiting: return .secondary
            case .running: return .accentColor
            case .done: return .green
            case .failed: return .orange
            }
        }
    }

    private func state(of step: DuckLink.Step) -> StepState {
        switch scanner.progress {
        case .idle:
            return .waiting
        case .running(let now):
            if step == now { return .running }
            return step.rawValue < now.rawValue ? .done : .waiting
        case .failed(let at, _):
            if step == at { return .failed }
            return step.rawValue < at.rawValue ? .done : .waiting
        case .done:
            return .done
        }
    }
}
