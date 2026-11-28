// The harness's screens (plan WI-M2-M7: plain test controls, not product UI; not judged against UX-4). AC-M2-28: the
// fixtures hash on screen, each input's script, start and stop, retake reason, network and key fields, export and
// "Remove key".

import SwiftUI
import TendIngestion

struct EvalRootView: View {
    @State private var session = EvalSession()

    var body: some View {
        NavigationStack {
            Form {
                EvalFixturesSection(session: session)
                if session.runner == nil {
                    EvalSetupSection(session: session)
                } else {
                    EvalRunSection(session: session)
                    EvalInputsSection(session: session)
                    EvalFinishSection(session: session)
                }
                if !session.status.isEmpty {
                    Section("Status") { Text(session.status).textSelection(.enabled) }
                }
            }
            .navigationTitle("TendEval")
        }
    }
}

/// The bundled fixtures and the build: the manifest hash and the commit (AC-M2-28 "Build path").
struct EvalFixturesSection: View {
    let session: EvalSession

    var body: some View {
        Section("Fixtures and build") {
            LabeledContent("Fixtures SHA-256") {
                Text(session.bundle?.fixturesSHA256 ?? "not loaded").font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if let bundle = session.bundle {
                ForEach(bundle.checks, id: \.name) { check in
                    LabeledContent(check.name, value: check.matches ? "matches manifest" : "does not match")
                }
                LabeledContent("Inputs", value: "\(bundle.fixtures.inputs.count)")
            }
            if let problem = session.bundleProblem { Text(problem) }
            LabeledContent("App commit") {
                Text(session.commitSHA).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }
}

struct EvalSetupSection: View {
    @Bindable var session: EvalSession

    var body: some View {
        Section("Run setup") {
            TextField("Operator", text: $session.operatorName)
            TextField("Network kind", text: $session.networkKind)
            TextField("Download (Mbps)", text: $session.downMbps).keyboardType(.numberPad)
            TextField("Upload (Mbps)", text: $session.upMbps).keyboardType(.numberPad)
            TextField("Latency (ms)", text: $session.latencyMs).keyboardType(.numberPad)
            Picker("Route", selection: $session.routeChoice) {
                ForEach(EvalRouteChoice.allCases) { Text($0.label).tag($0) }
            }
            if session.routeChoice.provider != nil {
                Toggle("Always use the cloud model", isOn: $session.alwaysCloud)
                SecureField("\(session.routeChoice.label) key", text: $session.keyText)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            LabeledContent("Model", value: session.kind.modelID)
            LabeledContent("Sampling", value: session.kind.sampling)
        }
        Section {
            Button("Start run") { Task { await session.startRun() } }
                .disabled(session.setupProblem != nil || session.isBusy)
            if let problem = session.setupProblem { Text(problem) }
        }
    }
}

struct EvalRunSection: View {
    let session: EvalSession

    var body: some View {
        Section("Run") {
            LabeledContent("Route", value: session.routeChoice.label)
            LabeledContent("Attempts", value: "\(session.attempts.count)")
            if session.kind.provider == nil {
                if let cold = session.coldStart {
                    LabeledContent("Cold start \(cold.inputID)", value: cold.ttfiMs.map { "\($0) ms" } ?? "none")
                } else {
                    Button("Cold start (input 1, not scored)") { Task { await session.runColdStart() } }
                        .disabled(!session.canColdStart)
                }
            }
        }
    }
}

struct EvalInputsSection: View {
    let session: EvalSession

    var body: some View {
        Section("Inputs") {
            ForEach(session.inputs, id: \.id) { input in
                NavigationLink {
                    EvalInputView(session: session, input: input)
                } label: {
                    LabeledContent(input.id, value: "\(input.mode == .voice ? "voice" : "text"), "
                                   + "\(session.attemptCount(input.id)) done")
                }
            }
        }
    }
}

/// One input: its script, start (and stop for voice), retake reason, and the last result.
struct EvalInputView: View {
    @Bindable var session: EvalSession
    let input: EvalFixtureInput

    var body: some View {
        Form {
            Section("Script (\(input.mode == .voice ? "read aloud" : "fed verbatim"))") {
                Text(input.text).font(.title3)
            }
            Section {
                if input.mode == .voice {
                    if session.isRecording {
                        Button("Stop") { session.stopVoice() }
                        if !session.liveText.isEmpty { Text(session.liveText).foregroundStyle(.secondary) }
                    } else {
                        if session.attemptCount(input.id) == 1 {
                            TextField("Retake reason (a misread)", text: $session.retakeReason)
                        }
                        Button("Start recording") { Task { await session.startVoice(input) } }
                            .disabled(session.nextAttemptProblem(input) != nil)
                    }
                } else {
                    Button("Run") { Task { await session.runText(input) } }
                        .disabled(session.nextAttemptProblem(input) != nil)
                }
                if let problem = session.nextAttemptProblem(input), !session.isRecording { Text(problem) }
            }
            ForEach(session.attempts.filter { $0.inputID == input.id }, id: \.attempt) { attempt in
                Section("Attempt \(attempt.attempt)") {
                    LabeledContent("Outcome", value: attempt.outcome.rawValue)
                    LabeledContent("TTFI", value: attempt.ttfiMs.map { "\($0) ms" } ?? "none")
                    LabeledContent("Total", value: "\(attempt.totalMs) ms")
                    LabeledContent("Drafts", value: "\(attempt.drafts.count)")
                    LabeledContent("Committed", value: "\(attempt.committed.count)")
                    if let transcript = attempt.transcript { Text(transcript).foregroundStyle(.secondary) }
                }
            }
            if !session.status.isEmpty { Section("Status") { Text(session.status) } }
        }
        .navigationTitle(input.id)
        .task { await session.show(input.id) }
    }
}

struct EvalFinishSection: View {
    let session: EvalSession

    var body: some View {
        Section("Finish") {
            Button("Save results file") { session.export() }
                .disabled(!session.canExport)
            if let name = session.exportedName, let sha = session.exportedSHA256 {
                LabeledContent("File") { Text(name).font(.caption.monospaced()).textSelection(.enabled) }
                LabeledContent("SHA-256") { Text(sha).font(.caption.monospaced()).textSelection(.enabled) }
            }
            if session.kind.provider != nil {
                Button("Remove key") { Task { await session.removeKey() } }
                    .disabled(!session.canRemoveKey)
                if session.keyRemoved { Text("Key removed.") }
            }
        }
    }
}
