import Foundation
import Observation

/// Pure scheduling policy. Every item retains just its last dispatched cutoff.
struct AutomaticInsightSchedule {
    static let interval: TimeInterval = 45
    static let minimumNewCharacters = 80
    struct Stamp { let date: Date; let characters: Int }
    var startedAt: Date
    var initialCharacters: Int
    private(set) var dispatched: [UUID: Stamp] = [:]

    func isDue(_ id: UUID, now: Date, finalizedCharacters: Int) -> Bool {
        let previous = dispatched[id] ?? Stamp(date: startedAt, characters: initialCharacters)
        return now.timeIntervalSince(previous.date) >= Self.interval
            && finalizedCharacters - previous.characters >= Self.minimumNewCharacters
    }

    mutating func noteDispatch(_ id: UUID, now: Date, finalizedCharacters: Int) {
        dispatched[id] = Stamp(date: now, characters: finalizedCharacters)
    }
}

struct InsightKey: Hashable {
    let meetingID: UUID
    let definitionID: UUID
}

@MainActor
@Observable
final class InsightEngine {
    static let maximumConcurrentRequests = 6

    enum State: Equatable {
        case queued
        case generating
        case saved
        case failed(String)
        case cancelled
        case unsaved(String)
    }

    private(set) var states: [InsightKey: State] = [:]
    private(set) var unsaved: [UUID: InsightSnapshotValue] = [:]
    private(set) var batchMeetingID: UUID?
    private let settings: AISettings
    private let history: MeetingHistoryStore
    private let providerFactory: () -> (any LLMProvider)?
    private let saveSnapshot: (InsightSnapshotValue) throws -> Void
    @ObservationIgnored private var tasks: [InsightKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var inputs: [InsightKey: InsightInput] = [:]
    @ObservationIgnored private var tokens: [InsightKey: UUID] = [:]
    @ObservationIgnored private var recordingID: UUID?
    @ObservationIgnored private var schedule: AutomaticInsightSchedule?
    @ObservationIgnored private var batchQueue: [InsightInput] = []
    @ObservationIgnored private var batchProvider: (any LLMProvider)?

    init(settings: AISettings, history: MeetingHistoryStore,
         providerFactory: (() -> (any LLMProvider)?)? = nil,
         saveSnapshot: ((InsightSnapshotValue) throws -> Void)? = nil) {
        self.settings = settings
        self.history = history
        self.providerFactory = providerFactory ?? { settings.makeProvider() }
        self.saveSnapshot = saveSnapshot ?? { try history.appendInsight($0) }
    }

    func startRecording(_ record: MeetingRecord, sections: [Section], now: Date = .now) {
        recordingID = record.id
        schedule = AutomaticInsightSchedule(startedAt: now,
            initialCharacters: InsightSource.capture(sections, includingProvisional: false).reduce(0) { $0 + $1.text.count })
    }

    func automaticTick(record: MeetingRecord, sections: [Section], vocabulary: [String],
                       elapsedSeconds: TimeInterval, now: Date = .now) {
        guard record.id == recordingID, record.meetingStatus == .recording,
              inputs.count < Self.maximumConcurrentRequests,
              let schedule, !inputs.values.contains(where: { $0.kind == .automatic }) else { return }
        let sources = InsightSource.capture(sections, includingProvisional: false)
        let characters = sources.reduce(0) { $0 + $1.text.count }
        let due = record.orderedDefinitions.filter {
            let key = InsightKey(meetingID: record.id, definitionID: $0.id)
            return $0.automaticallyUpdates && tasks[key] == nil && states[key] != .queued
                && !unsaved.values.contains { $0.input.meetingID == record.id && $0.input.configuration.id == key.definitionID }
                && schedule.isDue($0.id, now: now, finalizedCharacters: characters)
        }.sorted {
            (schedule.dispatched[$0.id]?.date ?? schedule.startedAt)
                < (schedule.dispatched[$1.id]?.date ?? schedule.startedAt)
        }
        guard let definition = due.first, providerFactory() != nil else { return }
        generate(record: record, configuration: definition.configuration, kind: .automatic,
                 sources: sources, vocabulary: vocabulary, elapsedSeconds: elapsedSeconds, now: now)
    }

    private func makeInput(record: MeetingRecord, configuration: InsightConfiguration, kind: InsightKind,
                   sources: [InsightSource], vocabulary: [String], elapsedSeconds: TimeInterval,
                   now: Date = .now) -> InsightInput {
        InsightInput(meetingID: record.id, configuration: configuration, kind: kind, requestedAt: now,
                     elapsedSeconds: elapsedSeconds, sources: sources, vocabulary: vocabulary,
                     additionalInstructions: kind == .summary ? record.orderedDefinitions.map(\.configuration) : [],
                     providerModel: settings.modelIdentity, contextTokenBudget: settings.insightContextTokenBudget)
    }

    func generate(record: MeetingRecord, configuration: InsightConfiguration, kind: InsightKind,
                  sources: [InsightSource], vocabulary: [String], elapsedSeconds: TimeInterval,
                  now: Date = .now) {
        if kind == .automatic && inputs.count >= Self.maximumConcurrentRequests { return }
        let input = makeInput(record: record, configuration: configuration, kind: kind,
                              sources: sources, vocabulary: vocabulary, elapsedSeconds: elapsedSeconds, now: now)
        let key = InsightKey(meetingID: record.id, definitionID: configuration.id)
        if let existing = inputs[key], input.analyzesSameContent(as: existing) { return }
        // A standalone manual selection supersedes older manual work. Generate All
        // instead fills the shared request capacity with independent batch items.
        if kind != .automatic {
            cancelBatch()
            for (otherKey, otherInput) in Array(inputs) where otherInput.kind != .automatic || otherKey == key {
                cancel(otherKey)
            }
        }
        cancel(key)
        dispatch(input, now: now)
    }

    func canGenerateAll(_ record: MeetingRecord) -> Bool {
        let ids = Set(record.definitions.map(\.id))
        return batchMeetingID == nil && record.meetingStatus != .draft && !ids.isEmpty
            && !unsaved.values.contains { $0.input.meetingID == record.id && ids.contains($0.input.configuration.id) }
    }

    func generateAll(record: MeetingRecord, sources: [InsightSource], vocabulary: [String],
                     elapsedSeconds: TimeInterval, now: Date = .now) {
        guard canGenerateAll(record) else { return }
        for (key, input) in Array(inputs) where input.kind != .automatic { cancel(key) }
        let requests = record.insightReadingOrder.map {
            makeInput(record: record, configuration: $0.configuration, kind: .manual,
                      sources: sources, vocabulary: vocabulary, elapsedSeconds: elapsedSeconds, now: now)
        }
        for input in requests { cancel(InsightKey(meetingID: record.id, definitionID: input.configuration.id)) }
        batchQueue = requests
        batchMeetingID = record.id
        batchProvider = providerFactory()
        for input in requests { states[InsightKey(meetingID: record.id, definitionID: input.configuration.id)] = .queued }
        dispatchBatch(now: now)
    }

    func cancelBatch() {
        guard let meetingID = batchMeetingID else { return }
        batchMeetingID = nil
        batchProvider = nil
        for input in batchQueue {
            states[InsightKey(meetingID: meetingID, definitionID: input.configuration.id)] = .cancelled
        }
        batchQueue.removeAll()
        for (key, input) in Array(inputs) where key.meetingID == meetingID && input.kind != .automatic { cancel(key) }
    }

    private func dispatchBatch(now: Date = .now) {
        guard let meetingID = batchMeetingID else { return }
        while !batchQueue.isEmpty && inputs.count < Self.maximumConcurrentRequests {
            dispatch(batchQueue.removeFirst(), now: now)
        }
        if batchQueue.isEmpty && !inputs.values.contains(where: { $0.meetingID == meetingID && $0.kind == .manual }) {
            batchMeetingID = nil
            batchProvider = nil
        }
    }

    private func dispatch(_ input: InsightInput, now: Date) {
        let key = InsightKey(meetingID: input.meetingID, definitionID: input.configuration.id)
        schedule?.noteDispatch(input.configuration.id, now: now,
                               finalizedCharacters: input.sources.reduce(0) { $0 + $1.text.count })
        do {
            guard let owner = try history.record(id: input.meetingID),
                  input.kind == .summary || owner.definitions.contains(where: { $0.id == input.configuration.id }) else {
                throw LLMError.invalidRequest("This meeting or insight item has been deleted.")
            }
            guard input.kind != .summary || owner.meetingStatus == .ended else {
                throw LLMError.invalidRequest("End the meeting before generating a full summary.")
            }
            let selectedProvider = input.kind == .manual && batchMeetingID == input.meetingID
                ? batchProvider : providerFactory()
            guard let provider = selectedProvider else { throw LLMError.notConfigured }
            let user = try InsightRequest.prepare(input)
            let token = UUID()
            tokens[key] = token
            inputs[key] = input
            states[key] = .generating
            tasks[key] = Task { @MainActor [weak self] in
                do {
                    let raw = try await provider.complete(system: InsightRequest.systemPrompt,
                                                          user: user, schema: InsightResult.responseSchema)
                    try Task.checkCancellation()
                    let result = try InsightResult.parse(raw, kind: input.kind)
                    guard let self, self.tokens[key] == token else { return }
                    guard let owner = try self.history.record(id: input.meetingID),
                          input.kind == .summary || owner.definitions.contains(where: { $0.id == input.configuration.id }) else {
                        self.cancel(key)
                        return
                    }
                    let value = InsightSnapshotValue(id: token, input: input, completedAt: Date(), result: result)
                    self.persist(value, key: key)
                    self.finish(key, token: token)
                } catch {
                    guard let self, self.tokens[key] == token else { return }
                    self.states[key] = error is CancellationError ? .cancelled : .failed(error.localizedDescription)
                    self.finish(key, token: token)
                }
            }
        } catch {
            states[key] = .failed(error.localizedDescription)
        }
    }

    func retrySave(_ id: UUID) {
        guard let value = unsaved[id] else { return }
        persist(value, key: InsightKey(meetingID: value.input.meetingID,
                                      definitionID: value.input.configuration.id))
    }

    func cancelMeeting(_ id: UUID, deleting: Bool = false) {
        if batchMeetingID == id { cancelBatch() }
        for key in Array(tasks.keys) where key.meetingID == id { cancel(key) }
        if recordingID == id { recordingID = nil; schedule = nil }
        if deleting {
            unsaved = unsaved.filter { $0.value.input.meetingID != id }
            states = states.filter { $0.key.meetingID != id }
        }
    }

    func cancel(_ key: InsightKey) {
        if states[key] == .queued {
            batchQueue.removeAll { $0.meetingID == key.meetingID && $0.configuration.id == key.definitionID }
            states[key] = .cancelled
        }
        if let task = tasks.removeValue(forKey: key) {
            task.cancel()
            inputs[key] = nil
            tokens[key] = nil
            states[key] = .cancelled
        }
        dispatchBatch()
    }

    private func persist(_ value: InsightSnapshotValue, key: InsightKey) {
        do {
            try saveSnapshot(value)
            unsaved[value.id] = nil
            states[key] = .saved
        } catch {
            unsaved[value.id] = value
            states[key] = .unsaved("Generated but not saved. Retry Save before quitting. \(error.localizedDescription)")
        }
    }

    private func finish(_ key: InsightKey, token: UUID) {
        guard tokens[key] == token else { return }
        tasks[key] = nil
        inputs[key] = nil
        tokens[key] = nil
        dispatchBatch()
    }
}
