import XCTest
@testable import SameWave

@MainActor
final class CaptionStabilityTests: XCTestCase {
    func testShortFinalFragmentsContinueTranslatingWithinTheSameSentence() throws {
        let store = CaptionStore()
        let fragments = ["I'd now like", "to", "quote from", "A great liberal."]
        for (index, fragment) in fragments.enumerated() {
            store.updateSource(fragment, speaker: .remote, isFinal: false)
            XCTAssertEqual(store.sections.count, 1)
            XCTAssertEqual(store.sections[0].sourceText, fragments.prefix(index + 1).joined(separator: " "))
            XCTAssertEqual(try XCTUnwrap(store.beginTranslation(id: 0)), index + 1)
            store.updateSource(fragment, speaker: .remote, isFinal: true)
            XCTAssertNil(store.beginTranslation(id: 0))
            XCTAssertEqual(store.sections[0].committedSource.count, index + 1)
        }
        XCTAssertEqual(store.sections[0].contentState, .sealed)
        store.updateSource("Democrats. A friend of Ted. Vladimir Lenin", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.sourceText), [fragments.joined(separator: " "),
                                                        "Democrats.", "A friend of Ted.", "Vladimir Lenin"])
        XCTAssertEqual(store.paragraphLayout.paragraphs.map(\.sectionIDs), [[0, 1, 2, 3]])
    }

    func testCommittedPrefixSurvivesNewHypothesisCorrectionsAndPauseExactlyOnce() throws {
        let store = CaptionStore()
        store.updateSource("I'd now like", speaker: .remote, isFinal: true)
        store.updateSource("to quote form", speaker: .remote, isFinal: false)
        store.updateSource("to quote from", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.sections[0].sourceText, "I'd now like to quote from")
        let generation = try XCTUnwrap(store.beginTranslation(id: 0))
        store.updateSource("to quote from", speaker: .remote, isFinal: true)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.updateSource("a great", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.endTurn(.remote), [0])
        XCTAssertEqual(store.endTurn(.remote), [])
        XCTAssertEqual(store.sections[0].sourceText, "I'd now like to quote from a great")
        XCTAssertEqual(store.sections[0].generation, generation)
        store.updateSource("After resume", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.sections.map(\.id), [0, 1])
    }

    func testShortFinalsStillRespectUnitSizeAndChineseJoining() {
        let store = CaptionStore()
        let words = (1...100).map { "word\($0)" }
        for word in words { store.updateSource(word, speaker: .remote, isFinal: true) }
        XCTAssertGreaterThan(store.sections.count, 2)
        XCTAssertTrue(store.sections.allSatisfy { $0.sourceText.count <= 247 })
        XCTAssertEqual(TranscriptText.join(store.sections.map(\.sourceText)), words.joined(separator: " "))
        store.clear()
        for fragment in ["我们", "现在", "讨论", "计划。"] {
            store.updateSource(fragment, speaker: .remote, isFinal: true)
        }
        XCTAssertEqual(store.sections.map(\.sourceText), ["我们现在讨论计划。"])
        XCTAssertEqual(store.sections[0].contentState, .sealed)
    }

    func testPunctuationDeadlineIncludesCommittedPrefixWithoutBeingResetByFinality() {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("The meeting is", speaker: .remote, isFinal: true, at: start)
        store.updateSource("on Friday.", speaker: .remote, isFinal: false, at: start.advanced(by: .seconds(1)))
        store.updateSource("on Friday.", speaker: .remote, isFinal: false,
                           at: start.advanced(by: .milliseconds(1_200)))
        XCTAssertEqual(store.nextDraftCommitDeadline, start.advanced(by: .milliseconds(1_700)))
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(1_700))), [0])
        store.updateSource("on Friday. Please join", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.sourceText), ["The meeting is on Friday.", "Please join"])
    }

    func testFollowingSentenceNeverRetranslatesOrReplacesPreviousCaption() throws {
        let store = CaptionStore()
        let first = "We need to move the meeting to Friday afternoon."
        let start = ContinuousClock.now
        store.updateSource(first, speaker: .remote, isFinal: false, at: start)
        let generation = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("我们需要把会议改到周五下午。", id: 0, generation: generation)
        let translation = store.sections[0].targetText
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(700))), [0])
        for suffix in ["Please", "Please notify", "Please notify everyone before lunch."] {
            store.updateSource(first + " " + suffix, speaker: .remote, isFinal: false)
            XCTAssertNil(store.beginTranslation(id: 0))
            XCTAssertEqual(store.sections[0].targetText, translation)
            XCTAssertEqual(store.sections[0].sourceText, first)
            XCTAssertEqual(store.sections[0].contentState, .sealed)
            XCTAssertEqual(store.sections[1].sourceText, suffix)
        }
        store.updateSource(first + " Please notify everyone before lunch.", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.count, 2)
        XCTAssertTrue(store.sections.allSatisfy { $0.committedSource.count == 1 && $0.interimSource.isEmpty })
        XCTAssertEqual(store.sections[0].targetText, translation)
    }

    func testPunctuationStabilityPromotesVisibleTranslationWithoutFinalizingRecognition() throws {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("Friday.", speaker: .remote, isFinal: false, at: start)
        let generation = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("周五。", id: 0, generation: generation)
        store.updateSource("Friday.", speaker: .remote, isFinal: false, at: start.advanced(by: .milliseconds(200)))
        XCTAssertEqual(store.nextDraftCommitDeadline, start.advanced(by: .milliseconds(700)))
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(699))), [])
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(700))), [0])
        XCTAssertEqual(store.sections[0].targetText, "周五。")
        XCTAssertEqual(store.sections[0].generation, generation)
        XCTAssertTrue(store.sections[0].committedSource.isEmpty)
        XCTAssertNil(store.beginTranslation(id: 0))
        store.updateSource("Friday. The agenda", speaker: .remote, isFinal: false,
                           at: start.advanced(by: .milliseconds(900)))
        XCTAssertEqual(store.sections.map(\.sourceText), ["Friday.", "The agenda"])
        store.updateSource("Friday. The agenda stays the same.", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.committedSource), [["Friday."], ["The agenda stays the same."]])
        XCTAssertEqual(store.endTurn(.remote), [])
    }

    func testChangedPunctuationDraftRestartsOnlyItsOwnStabilityDeadline() {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("Friday.", speaker: .remote, isFinal: false, at: start)
        store.updateSource("My question", speaker: .mine, isFinal: false, at: start.advanced(by: .milliseconds(50)))
        store.updateSource("Saturday.", speaker: .remote, isFinal: false, at: start.advanced(by: .milliseconds(100)))
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(700))), [])
        store.updateSource("My question continues", speaker: .mine, isFinal: false, at: start.advanced(by: .milliseconds(750)))
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(800))), [0])
        XCTAssertEqual(store.sections[1].contentState, .open)
    }

    func testContinuousUnpunctuatedSpeechHasBoundedIndependentCaptions() throws {
        let store = CaptionStore()
        let tokens = (1...120).map { "word\($0)" }
        let start = ContinuousClock.now
        var sealed: [Int: String] = [:]
        for count in 1...tokens.count {
            store.updateSource(tokens.prefix(count).joined(separator: " "), speaker: .remote,
                               isFinal: false, at: start.advanced(by: .milliseconds(count * 100)))
            for (id, source) in sealed { XCTAssertEqual(store.section(id: id)?.sourceText, source) }
            for section in store.sections where section.contentState == .sealed { sealed[section.id] = section.sourceText }
            XCTAssertEqual(store.sections.filter { $0.contentState == .open }.count, 1)
            XCTAssertTrue(store.sections.allSatisfy { $0.sourceText.count <= 247 })
        }
        XCTAssertGreaterThan(store.sections.count, 3)
        XCTAssertEqual(store.sections.map(\.sourceText).joined(separator: " "), tokens.joined(separator: " "))
        let ids = store.sections.map(\.id)
        store.updateSource(tokens.joined(separator: " "), speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.id), ids)
        XCTAssertEqual(store.sections.map(\.sourceText).joined(separator: " "), tokens.joined(separator: " "))
    }

    func testDirectFinalAndChineseCumulativeInputSplitAtSentenceBoundaries() {
        for text in ["First sentence. Second sentence! Third sentence?", "我们讨论计划。请通知大家！议程保持不变？"] {
            let store = CaptionStore()
            store.updateSource(text, speaker: .remote, isFinal: true)
            XCTAssertEqual(store.sections.count, 3)
            XCTAssertTrue(store.sections.allSatisfy { $0.contentState == .sealed })
            XCTAssertEqual(store.sections.map(\.sourceText).joined().filter { !$0.isWhitespace },
                           text.filter { !$0.isWhitespace })
        }
    }

    func testDecimalAbbreviationAndEllipsisDoNotCreateSpuriousCaptions() {
        let store = CaptionStore()
        store.updateSource("Dr. Smith expects 3.14 percent growth", speaker: .remote, isFinal: false)
        XCTAssertEqual(store.sections.count, 1)
        XCTAssertNil(store.nextDraftCommitDeadline)
        store.updateSource("Dr. Smith expects 3.14 percent growth...", speaker: .remote, isFinal: false)
        XCTAssertNil(store.nextDraftCommitDeadline)
    }

    func testFinalCorrectionOnlyRequestsTheChangedCaption() throws {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("We ship Friday. Please notify everyone.", speaker: .remote, isFinal: false, at: start)
        store.commitReadyDrafts(at: start.advanced(by: .milliseconds(700)))
        for section in store.sections { XCTAssertNotNil(store.beginTranslation(id: section.id)) }
        store.updateSource("We ship Saturday. Please notify everyone.", speaker: .remote, isFinal: true)
        XCTAssertNotNil(store.beginTranslation(id: 0))
        XCTAssertNil(store.beginTranslation(id: 1))
        XCTAssertEqual(store.sections.map(\.sourceText), ["We ship Saturday.", "Please notify everyone."])
    }

    func testTemporaryPunctuationCanDisappearAfterTheOldDeadlineWithoutSplitting() throws {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("I'd now like.", speaker: .remote, isFinal: false, at: start)
        let generation = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("我现在想。", id: 0, generation: generation)
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(300))), [])
        store.updateSource("I'd now like to quote from", speaker: .remote, isFinal: false,
                           at: start.advanced(by: .milliseconds(500)))
        XCTAssertNotNil(store.beginTranslation(id: 0))
        XCTAssertNil(store.nextDraftCommitDeadline)
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .seconds(1))), [])
        XCTAssertEqual(store.sections.map(\.sourceText), ["I'd now like to quote from"])
    }

    func testLateBoundaryConfirmationRejectsFullDraftTranslationsAndPreservesOwnership() throws {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("We ship Friday please notify everyone", speaker: .remote, isFinal: false, at: start)
        let oldGeneration = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("我们周五发货，请通知大家", id: 0, generation: oldGeneration)
        store.updateSource("We ship Friday. Please notify everyone", speaker: .remote, isFinal: false,
                           at: start.advanced(by: .milliseconds(200)))
        let pendingGeneration = try XCTUnwrap(store.beginTranslation(id: 0))
        store.updateSource("We ship Friday. Please notify everyone before lunch", speaker: .remote, isFinal: false,
                           at: start.advanced(by: .milliseconds(600)))
        XCTAssertEqual(store.nextDraftCommitDeadline, start.advanced(by: .milliseconds(900)))
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .milliseconds(900))), [0, 1])
        XCTAssertEqual(store.sections.map(\.sourceText), ["We ship Friday.", "Please notify everyone before lunch"])
        XCTAssertTrue(store.sections.allSatisfy { $0.targetText.isEmpty })
        XCTAssertFalse(store.failTranslation(id: 0, generation: pendingGeneration))
        XCTAssertEqual(store.sections[0].translationState, .pending)
        let headGeneration = try XCTUnwrap(store.beginTranslation(id: 0))
        store.applyTranslation("Stale full draft", id: 0, generation: pendingGeneration)
        store.failTranslation(id: 0, generation: pendingGeneration)
        XCTAssertTrue(store.sections[0].targetText.isEmpty)
        XCTAssertEqual(store.sections[0].translationState, .translating)
        store.applyTranslation("我们周五发货。", id: 0, generation: headGeneration)
        store.updateSource("We ship Saturday. Please notify everyone before lunch.", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.sourceText), ["We ship Saturday.", "Please notify everyone before lunch."])
        XCTAssertEqual(store.sections.map(\.committedSource), [["We ship Saturday."], ["Please notify everyone before lunch."]])
        XCTAssertEqual(store.endTurn(.remote), [])
    }

    func testBoundaryAcrossCommittedPrefixAndInterimRetainsSourceThroughStop() {
        for fragments in [["I'd now like", "to quote from a speaker. The next topic"],
                          ["我们现在", "讨论计划。请通知大家"]] {
            let store = CaptionStore()
            let start = ContinuousClock.now
            store.updateSource(fragments[0], speaker: .remote, isFinal: true, at: start)
            store.updateSource(fragments[1], speaker: .remote, isFinal: false, at: start)
            let original = store.sections[0].sourceText
            store.commitReadyDrafts(at: start.advanced(by: .milliseconds(700)))
            XCTAssertEqual(store.sections.count, 2)
            XCTAssertEqual(TranscriptText.join(store.sections.map(\.sourceText)), original)
            store.endTurn(.remote)
            XCTAssertEqual(TranscriptText.join(store.sections.map(\.sourceText)), original)
            XCTAssertTrue(store.sections.allSatisfy { $0.interimSource.isEmpty })
        }
    }

    func testFinalConfirmsLateSentencesAndKeepsUnpunctuatedTailOpen() {
        let store = CaptionStore()
        store.updateSource("First sentence second sentence third", speaker: .remote, isFinal: false)
        store.updateSource("First sentence. Second sentence. Third", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.map(\.sourceText), ["First sentence.", "Second sentence.", "Third"])
        XCTAssertEqual(store.sections.map(\.contentState), [.sealed, .sealed, .open])
        store.updateSource("continues", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections.last?.sourceText, "Third continues")
    }

    func testNaturalSentenceAndLongClauseArePreferredToTheFormerCharacterCut() {
        let store = CaptionStore()
        let first = "These short sentences belong together in one readable paragraph the earlier words should stay in place while the current sentence continues to grow."
        let words = first.split(separator: " ")
        for count in words.indices {
            store.updateSource(words[...count].joined(separator: " "), speaker: .remote, isFinal: false)
            XCTAssertEqual(store.sections.count, 1)
        }
        store.updateSource(first, speaker: .remote, isFinal: true)
        let clause = "A useful translation should remain readable throughout a long discussion and follow the speaker without repeated context,"
        let start = ContinuousClock.now
        store.updateSource(clause + " while the next thought develops", speaker: .remote, isFinal: false, at: start)
        store.commitReadyDrafts(at: start.advanced(by: .milliseconds(700)))
        XCTAssertEqual(store.sections.map(\.sourceText), [first, clause, "while the next thought develops"])
    }

    func testLatePunctuationDoesNotMoveExistingWordsAcrossAnotherSpeaker() {
        let store = CaptionStore()
        let start = ContinuousClock.now
        store.updateSource("We ship Friday please notify everyone", speaker: .remote, isFinal: false, at: start)
        store.updateSource("My question", speaker: .mine, isFinal: false, at: start)
        store.updateSource("We ship Friday. Please notify everyone", speaker: .remote, isFinal: false,
                           at: start.advanced(by: .milliseconds(100)))
        XCTAssertNil(store.nextDraftCommitDeadline)
        XCTAssertEqual(store.commitReadyDrafts(at: start.advanced(by: .seconds(1))), [])
        XCTAssertEqual(store.sections.map(\.speaker), [.remote, .mine])
        store.updateSource("We ship Friday. Please notify everyone.", speaker: .remote, isFinal: true)
        XCTAssertEqual(store.sections[0].sourceText, "We ship Friday. Please notify everyone.")
        XCTAssertEqual(store.sections[0].contentState, .sealed)
    }

    func testLargeBatchedInterimUsesExistingSentenceBeforeTheHardLimit() {
        let store = CaptionStore()
        let first = "This complete sentence should remain together."
        let tail = "The next long sentence contains " + (1...55).map { "word\($0)" }.joined(separator: " ")
        store.updateSource(first + " " + tail, speaker: .remote, isFinal: false)
        XCTAssertEqual(store.sections.first?.sourceText, first)
        XCTAssertTrue(store.sections.allSatisfy { $0.sourceText.count <= 247 })
        XCTAssertEqual(TranscriptText.join(store.sections.map(\.sourceText)), first + " " + tail)
        store.updateSource(first + " " + tail, speaker: .remote, isFinal: true)
        XCTAssertEqual(TranscriptText.join(store.sections.map(\.sourceText)), first + " " + tail)
    }
}
