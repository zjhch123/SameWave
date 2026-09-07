import XCTest
@testable import SameWave

@MainActor
final class CaptionStoreTests: XCTestCase {
    func testContinuousOverlapKeepsTwoReadableParagraphsUntilSpeakerReturnsAfterInactivity() {
        let store = CaptionStore()
        let start = ContinuousClock.now
        var remote = "The release"
        var mine = "My question"
        store.updateSource(remote, speaker: .remote, isFinal: false, at: start)
        store.updateSource(mine, speaker: .mine, isFinal: false, at: start.advanced(by: .milliseconds(100)))
        for index in 1...20 {
            remote += " remote\(index)"
            mine += " mine\(index)"
            store.updateSource(remote, speaker: .remote, isFinal: false, at: start.advanced(by: .milliseconds(index * 200)))
            store.updateSource(mine, speaker: .mine, isFinal: false, at: start.advanced(by: .milliseconds(index * 200 + 100)))
        }
        XCTAssertEqual(store.sections.map(\.sourceText), [remote, mine])
        XCTAssertEqual(store.sections.map(\.contentState), [.open, .open])
        // A correction at 4.9 seconds must not hide the gap since actual growth at 4.
        store.updateSource(remote + ".", speaker: .remote, isFinal: false, at: start.advanced(by: .milliseconds(4_900)))
        store.updateSource(remote + ". Continuing", speaker: .remote, isFinal: false, at: start.advanced(by: .seconds(5)))
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine, .remote])
        XCTAssertEqual(store.sections.last?.sourceText, "Continuing")
    }

    func testInactivityWithoutAnInterveningSpeakerDoesNotSplitParagraph() {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("The release", speaker: .remote, isFinal: false, at: start)
        store.updateSource("The release is ready", speaker: .remote, isFinal: false, at: start.advanced(by: .seconds(30)))
        XCTAssertEqual(store.sections.map(\.sourceText), ["The release is ready"])
    }

    func testFinalCommitSwitchesSpeakerAndSealsPreviousSection() {
        let store = CaptionStore()
        XCTAssertEqual(store.updateSource("Hello", speaker: .remote, isFinal: true), [0])
        XCTAssertEqual(store.updateSource("Hi", speaker: .mine, isFinal: true), [0, 1])
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine])
        XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .open])
    }

    func testContinuationOpensThirdTurnBeforeEitherRecognizerFinalizesInBothSpeakerOrders() {
        for (first, second): (Speaker, Speaker) in [(.remote, .mine), (.mine, .remote)] {
            let store = CaptionStore()
            store.updateSource("The release is ready", speaker: first, isFinal: false, at: .now.advanced(by: .seconds(-2)))
            store.updateSource("I have a question", speaker: second, isFinal: false)
            XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .open])
            XCTAssertEqual(store.updateSource("The release is ready for review", speaker: first, isFinal: false), [0, 2])
            XCTAssertEqual(store.sections.map(\.speaker), [first, second, first])
            XCTAssertEqual(store.sections.map(\.sourceText), ["The release is ready", "I have a question", "for review"])
            XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .open, .open])
            XCTAssertTrue(store.sections.allSatisfy { $0.committedSource.isEmpty })
            XCTAssertEqual(store.sections[2].priorContext, ["The release is ready"])
        }
    }

    func testLateFinalCorrectsAllOwnedFragmentsWithoutReopeningOldTurns() {
        let store = CaptionStore()
        store.updateSource("The release is ready", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("I have a question", speaker: .mine, isFinal: false)
        store.updateSource("The release is ready for review", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.updateSource("The release was ready for review.", speaker: .remote, isFinal: true), [0, 2])
        XCTAssertEqual(store.updateSource("I had a question.", speaker: .mine, isFinal: true), [1])
        XCTAssertEqual(store.sections.map(\.committedSource), [["The release was ready"], ["I had a question."], ["for review."]])
        XCTAssertTrue(store.sections.allSatisfy { $0.interimSource.isEmpty })
        XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .sealed, .open])
        store.updateSource("Tomorrow works.", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.last?.sourceText, "for review. Tomorrow works.")
    }

    func testCorrectionsDoNotTakeFloorFromOtherSpeaker() {
        let store = CaptionStore()
        store.updateSource("we ship on fryday", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("My reply", speaker: .mine, isFinal: false)
        for text in ["We ship on Friday.", "We will ship on Friday!", "We ship Friday."] {
            store.updateSource(text, speaker: .remote, isFinal: false)
            XCTAssertEqual(store.sections.count, 2)
            XCTAssertEqual(store.sections[0].sourceText, text)
            XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .open])
        }
        store.updateSource("My reply continues", speaker: .mine, isFinal: false)
        XCTAssertEqual(store.sections.count, 2)
        XCTAssertEqual(store.sections[1].sourceText, "My reply continues")
    }

    func testRepeatedInterruptionsPreserveEachAddedWordOnce() {
        let store = CaptionStore()
        var first = "alpha"
        var second = "beta"
        let start = ContinuousClock.now
        store.updateSource(first, speaker: .remote, isFinal: false, at: start)
        store.updateSource(second, speaker: .mine, isFinal: false, at: start.advanced(by: .seconds(2)))
        for index in 1...20 {
            first += " remote\(index)"
            second += " mine\(index)"
            store.updateSource(first, speaker: .remote, isFinal: false, at: start.advanced(by: .seconds(index * 4)))
            store.updateSource(second, speaker: .mine, isFinal: false, at: start.advanced(by: .seconds(index * 4 + 2)))
        }
        store.updateSource(first + ".", speaker: .remote, isFinal: true)
        store.updateSource(second + ".", speaker: .mine, isFinal: true)
        XCTAssertEqual(store.sections.count, 42)
        XCTAssertEqual(store.sections.filter { $0.speaker == .remote }.map(\.sourceText).joined(separator: " "), first + ".")
        XCTAssertEqual(store.sections.filter { $0.speaker == .mine }.map(\.sourceText).joined(separator: " "), second + ".")
        XCTAssertEqual(store.sections.filter { $0.contentState == .open }.map(\.id), [41])
        XCTAssertTrue(store.sections.allSatisfy { $0.interimSource.isEmpty })
    }

    func testShortFinalReplyInterruptsLongUnfinishedHypothesis() {
        let store = CaptionStore()
        store.updateSource("We can ship", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("Yes.", speaker: .mine, isFinal: true)
        store.updateSource("We can ship tomorrow.", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.sourceText), ["We can ship", "Yes.", "tomorrow."])
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine, .remote])
    }

    func testRepeatedWordsAreNewSpeechAndPunctuationStaysWithSource() {
        let store = CaptionStore()
        store.updateSource("Hello", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("Yes", speaker: .mine, isFinal: false)
        store.updateSource("Hello, hello!", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.sourceText), ["Hello,", "Yes", "hello!"])
    }

    func testNativeEnglishCumulativeSnapshotsWithInterleavedReplies() {
        // Captured from DictationTranscriber.progressiveLongDictation on macOS 26.
        // Interim audioTimeRange covered the entire hypothesis; word times arrived
        // only with the final. Replay the text through the production store.
        let store = CaptionStore()
        let start = ContinuousClock.now
        for text in ["This", "This is a live caption test"] {
            store.updateSource(text, speaker: .remote, isFinal: false, at: start)
        }
        store.updateSource("I agree", speaker: .mine, isFinal: false, at: start.advanced(by: .seconds(2)))
        for text in ["This is a live caption test we",
                     "This is a live caption test. We are review",
                     "This is a live caption test we are reviewing"] {
            store.updateSource(text, speaker: .remote, isFinal: false, at: start.advanced(by: .seconds(4)))
        }
        store.updateSource("I agree please continue", speaker: .mine, isFinal: true, at: start.advanced(by: .seconds(6)))
        store.updateSource("This is a live caption test. We are reviewing the release plan today.",
                           speaker: .remote, isFinal: false, at: start.advanced(by: .seconds(8)))
        let final = "This is a live caption test. We are reviewing the release plan today. "
            + "The engineering team will finish the review on Friday. Please keep showing the translation "
            + "while I continue to speak we can see each sentences. It arrives and the meeting should remain responsive. "
            + "The final decision is to review the results tomorrow."
        store.updateSource(final, speaker: .remote, isFinal: true, at: start.advanced(by: .seconds(9)))
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine, .remote, .mine, .remote])
        XCTAssertEqual(store.sections[0].sourceText, "This is a live caption test.")
        XCTAssertEqual(store.sections[2].sourceText, "We are reviewing")
        XCTAssertEqual(store.sections.filter { $0.speaker == .remote }.map(\.sourceText).joined(separator: " "), final)
        XCTAssertTrue(store.sections.allSatisfy { $0.interimSource.isEmpty })
    }

    func testLateCorrectionSchedulesEveryChangedFragmentAndDeduplicatesUnchangedSource() throws {
        let store = CaptionStore()
        store.updateSource("We ship", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("Yes", speaker: .mine, isFinal: true)
        store.updateSource("We ship tomorrow", speaker: .remote, isFinal: false)
        for section in store.sections { XCTAssertNotNil(store.beginTranslation(id: section.id)) }
        let affected = store.updateSource("We shipped yesterday.", speaker: .remote, isFinal: true)
        XCTAssertEqual(affected, [0, 2])
        XCTAssertEqual(affected.compactMap { store.beginTranslation(id: $0) }, [2, 2])
        XCTAssertNil(store.beginTranslation(id: 1))
        store.applyTranslation("Old translation", id: 0, generation: 1)
        XCTAssertEqual(store.sections[0].translationState, .translating)
        store.applyTranslation("Corrected translation", id: 0, generation: 2)
        XCTAssertEqual(store.sections[0].translationState, .done)
    }

    func testChineseContinuationAndEnglishTermsKeepTheirTurn() {
        let store = CaptionStore()
        store.updateSource("我们讨论计划", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("好的", speaker: .mine, isFinal: false)
        store.updateSource("我们讨论计划，然后检查 SwiftUI。", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine, .remote])
        XCTAssertEqual(store.sections.filter { $0.speaker == .remote }.map(\.sourceText).joined(), "我们讨论计划，然后检查 SwiftUI。")
        XCTAssertTrue(store.sections[2].sourceText.contains("SwiftUI"))
    }

    func testRetractedContinuationRemovesEmptySectionAndRejectsItsLateTranslation() throws {
        let store = CaptionStore()
        store.updateSource("We ship", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("Yes", speaker: .mine, isFinal: true)
        store.updateSource("We ship tomorrow", speaker: .remote, isFinal: false)
        let generation = try XCTUnwrap(store.beginTranslation(id: 2))
        store.updateSource("We ship", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.applyTranslation("Tomorrow", id: 2, generation: generation)
        XCTAssertEqual(store.sections.map(\.id), [0, 1])
        store.updateSource("We ship Friday", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.sections.map(\.id), [0, 1, 3])
        XCTAssertEqual(store.sections.map(\.sourceText), ["We ship", "Yes", "Friday"])
    }

    func testSeventhSentenceStartsNewSectionWithFrozenBoundedContext() {
        for useInterim in [false, true] {
            let store = CaptionStore()
            for index in 1...7 {
                if useInterim { store.updateSource("sentence \(index)", speaker: .remote, isFinal: false) }
                store.updateSource("sentence \(index)", speaker: .remote, isFinal: true)
            }
            XCTAssertEqual(store.sections.count, 2)
            XCTAssertEqual(store.sections[0].committedSource.count, 6)
            XCTAssertEqual(store.sections[1].committedSource, ["sentence 7"])
            XCTAssertEqual(store.sections[1].priorContext, (2...6).map { "sentence \($0)" })
            store.updateSource("sentence 8", speaker: .remote, isFinal: true)
            XCTAssertEqual(store.sections[1].priorContext, (2...6).map { "sentence \($0)" })
        }
    }

    func testStoppingBothSpeakersPreservesEveryPendingFragmentExactlyOnce() {
        let store = CaptionStore()
        store.updateSource("Finished sentence.", speaker: .remote, isFinal: true)
        store.updateSource("Still speaking", speaker: .remote, isFinal: false, at: .now.advanced(by: .seconds(-2)))
        store.updateSource("My reply", speaker: .mine, isFinal: false)
        store.updateSource("Still speaking after the reply", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.endTurn(.remote), [0, 2])
        XCTAssertEqual(store.endTurn(.mine), [1])
        XCTAssertEqual(store.sections.map(\.sourceText), ["Finished sentence. Still speaking", "My reply", "after the reply"])
        XCTAssertTrue(store.sections.allSatisfy { $0.contentState == .sealed && $0.interimSource.isEmpty })
        XCTAssertEqual(store.endTurn(.remote), [])
        XCTAssertEqual(store.updateSource("After resume", speaker: .remote, isFinal: true), [3])
    }

    func testEmptyInterimsDoNotCreateOrInterruptSections() {
        let store = CaptionStore()
        XCTAssertEqual(store.updateSource("  ", speaker: .remote, isFinal: false), [])
        XCTAssertTrue(store.sections.isEmpty)
        store.updateSource("Remote", speaker: .remote, isFinal: true)
        for text in ["\n", "..."] {
            XCTAssertEqual(store.updateSource(text, speaker: .mine, isFinal: false), [])
        }
        XCTAssertEqual(store.sections.count, 1)
        XCTAssertEqual(store.sections[0].contentState, .open)
    }

    func testRestoreAndClearDiscardHypothesesAndKeepIDsConsistent() {
        let store = CaptionStore()
        store.updateSource("Discarded live state", speaker: .mine, isFinal: false)
        store.restore(sections: [
            (id: 4, speaker: .remote, source: "earlier context", target: "上文", startedAt: .now)
        ])
        XCTAssertEqual(store.updateSource("new sentence", speaker: .remote, isFinal: true), [5])
        XCTAssertEqual(store.sections.last?.priorContext, ["earlier context"])
        XCTAssertEqual(store.updateSource("My next sentence", speaker: .mine, isFinal: false), [5, 6])
        store.clear()
        XCTAssertEqual(store.updateSource("My next sentence", speaker: .mine, isFinal: true), [0])
        XCTAssertEqual(store.sections.map(\.sourceText), ["My next sentence"])
    }

    func testRestoreDoesNotPretendMissingTranslationsAreStillRunning() {
        let store = CaptionStore()
        store.restore(sections: [
            (id: 0, speaker: .remote, source: "Saved source", target: "", startedAt: .now),
            (id: 1, speaker: .mine, source: "Translated source", target: "已翻译", startedAt: .now)
        ])
        XCTAssertEqual(store.sections.map(\.translationState), [.failed, .done])
        XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .sealed])
        XCTAssertEqual(store.sections[0].sourceText, "Saved source")
    }

    func testContinuousSpeechPublishesProgressBeforeLatestGenerationCompletes() throws {
        let store = CaptionStore()
        store.updateSource("hello", speaker: .remote, isFinal: false)
        let first = try XCTUnwrap(store.beginTranslation(id: 0))
        store.updateSource("hello world", speaker: .remote, isFinal: false)
        let second = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("你好", id: 0, generation: first)
        XCTAssertEqual(store.sections[0].targetText, "你好")
        XCTAssertEqual(store.sections[0].translationState, .translating)
        store.applyTranslation("你好世界", id: 0, generation: second)
        XCTAssertEqual(store.sections[0].translationState, .done)
        store.applyTranslation("旧", id: 0, generation: first)
        store.failTranslation(id: 0, generation: first)
        XCTAssertEqual(store.sections[0].targetText, "你好世界")
        XCTAssertEqual(store.sections[0].translationState, .done)
        store.updateSource("hello world again", speaker: .remote, isFinal: false)
        XCTAssertNotNil(store.beginTranslation(id: 0))
        XCTAssertEqual(store.sections[0].translationState, .translating)
    }

    func testDuplicateInterimFinalAndSealDoNotInvalidateInFlightTranslation() throws {
        let store = CaptionStore()
        store.updateSource("hello", speaker: .remote, isFinal: false)
        let generation = try XCTUnwrap(store.beginTranslation(id: 0))
        store.updateSource("hello", speaker: .remote, isFinal: false)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.updateSource("hello", speaker: .remote, isFinal: true)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.endTurn(.remote)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.applyTranslation("你好", id: 0, generation: generation)
        XCTAssertEqual(store.sections[0].translationState, .done)
    }

    func testEmptyTranslationFailsAndSameSourceCanRetry() throws {
        let store = CaptionStore()
        store.updateSource("hello", speaker: .remote, isFinal: true)
        let first = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("  ", id: 0, generation: first)
        XCTAssertEqual(store.sections[0].translationState, .failed)
        let retry = try XCTUnwrap(store.beginTranslation(id: 0))
        XCTAssertGreaterThan(retry, first)
        store.applyTranslation("你好", id: 0, generation: retry)
        XCTAssertEqual(store.sections[0].translationState, .done)
        XCTAssertEqual(store.sections[0].sourceText, "hello")
    }
}
