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
    private(set) var batchMeetingIDs: Set<UUID> = []
    private let settings: AISettings
    private let history: MeetingHistoryStore
    private let providerFactory: () -> (any LLMProvider)?
    private let saveSnapshot: (InsightSnapshotValue) throws -> Void
    @ObservationIgnored private var tasks: [InsightKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var inputs: [InsightKey: InsightInput] = [:]
    @ObservationIgnored private var tokens: [InsightKey: UUID] = [:]
    @ObservationIgnored private var recordingID: UUID?
    @ObservationIgnored private var schedule: AutomaticInsightSchedule?
    private struct PendingRequest {
        let input: InsightInput
        let provider: (any LLMProvider)?
        var key: InsightKey { InsightKey(meetingID: input.meetingID, definitionID: input.configuration.id) }
    }
    @ObservationIgnored private var queue: [PendingRequest] = []

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
        let existing = inputs[key] ?? queue.first(where: { $0.key == key })?.input
        if let existing, input.analyzesSameContent(as: existing) { return }
        // Replacement requests affect only their own meeting; navigation owns no work.
        if kind != .automatic {
            removeBatch(record.id)
            for (otherKey, otherInput) in Array(inputs)
                where otherKey.meetingID == record.id && otherInput.kind != .automatic {
                removeRequest(otherKey)
            }
            for pending in queue where pending.key.meetingID == record.id && pending.input.kind != .automatic {
                removeRequest(pending.key)
            }
        }
        removeRequest(key)
        enqueue(input, provider: providerFactory())
        dispatchQueued(now: now)
    }

    func isWorking(on meetingID: UUID) -> Bool {
        states.contains { $0.key.meetingID == meetingID && ($0.value == .generating || $0.value == .queued) }
    }

    func canGenerateAll(_ record: MeetingRecord) -> Bool {
        let ids = Set(record.definitions.map(\.id))
        return !batchMeetingIDs.contains(record.id) && record.meetingStatus != .draft && !ids.isEmpty
            && !unsaved.values.contains { $0.input.meetingID == record.id && ids.contains($0.input.configuration.id) }
    }

    func generateAll(record: MeetingRecord, sources: [InsightSource], vocabulary: [String],
                     elapsedSeconds: TimeInterval, now: Date = .now) {
        guard canGenerateAll(record) else { return }
        for (key, input) in Array(inputs) where key.meetingID == record.id && input.kind != .automatic {
            removeRequest(key)
        }
        for pending in queue where pending.key.meetingID == record.id && pending.input.kind != .automatic {
            removeRequest(pending.key)
        }
        let provider = providerFactory()
        for definition in record.insightReadingOrder {
            let input = makeInput(record: record, configuration: definition.configuration, kind: .manual,
                                  sources: sources, vocabulary: vocabulary, elapsedSeconds: elapsedSeconds, now: now)
            removeRequest(InsightKey(meetingID: record.id, definitionID: definition.id))
            enqueue(input, provider: provider)
        }
        batchMeetingIDs.insert(record.id)
        dispatchQueued(now: now)
    }

    func cancelBatch(_ meetingID: UUID) {
        removeBatch(meetingID)
        dispatchQueued()
    }

    private func removeBatch(_ meetingID: UUID) {
        guard batchMeetingIDs.remove(meetingID) != nil else { return }
        for pending in queue where pending.key.meetingID == meetingID && pending.input.kind == .manual {
            removeRequest(pending.key)
        }
        for (key, input) in Array(inputs) where key.meetingID == meetingID && input.kind == .manual {
            removeRequest(key)
        }
    }

    private func enqueue(_ input: InsightInput, provider: (any LLMProvider)?) {
        let pending = PendingRequest(input: input, provider: provider)
        queue.append(pending)
        states[pending.key] = .queued
    }

    private func dispatchQueued(now: Date = .now) {
        while !queue.isEmpty && inputs.count < Self.maximumConcurrentRequests {
            dispatch(queue.removeFirst(), now: now)
        }
        batchMeetingIDs = batchMeetingIDs.filter { id in
            queue.contains { $0.input.meetingID == id && $0.input.kind == .manual }
                || inputs.values.contains { $0.meetingID == id && $0.kind == .manual }
        }
    }

    private func dispatch(_ pending: PendingRequest, now: Date) {
        let input = pending.input
        let key = pending.key
        if recordingID == input.meetingID {
            schedule?.noteDispatch(input.configuration.id, now: now,
                                   finalizedCharacters: input.sources.reduce(0) { $0 + $1.text.count })
        }
        do {
            guard let owner = try history.record(id: input.meetingID),
                  input.kind == .summary || owner.definitions.contains(where: { $0.id == input.configuration.id }) else {
                throw LLMError.invalidRequest("This meeting or insight item has been deleted.")
            }
            guard input.kind != .summary || owner.meetingStatus == .ended else {
                throw LLMError.invalidRequest("End the meeting before generating a full summary.")
            }
            guard let provider = pending.provider else { throw LLMError.notConfigured }
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

    /// Pausing capture stops automatic scheduling, but explicit requests keep their frozen input.
    func stopRecording(_ id: UUID) {
        if recordingID == id { recordingID = nil; schedule = nil }
        for (key, input) in Array(inputs) where key.meetingID == id && input.kind == .automatic {
            removeRequest(key)
        }
        dispatchQueued()
    }

    func cancelMeeting(_ id: UUID, deleting: Bool = false) {
        removeBatch(id)
        for pending in queue where pending.key.meetingID == id { removeRequest(pending.key) }
        for key in Array(tasks.keys) where key.meetingID == id { removeRequest(key) }
        if recordingID == id { recordingID = nil; schedule = nil }
        if deleting {
            unsaved = unsaved.filter { $0.value.input.meetingID != id }
            states = states.filter { $0.key.meetingID != id }
        }
        dispatchQueued()
    }

    func cancel(_ key: InsightKey) {
        removeRequest(key)
        dispatchQueued()
    }

    private func removeRequest(_ key: InsightKey) {
        if states[key] == .queued {
            queue.removeAll { $0.key == key }
            states[key] = .cancelled
        }
        if let task = tasks.removeValue(forKey: key) {
            task.cancel()
            inputs[key] = nil
            tokens[key] = nil
            states[key] = .cancelled
        }
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
        dispatchQueued()
    }
}
