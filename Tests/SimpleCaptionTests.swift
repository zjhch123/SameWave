import XCTest
@testable import SameWave

final class SimpleCaptionTests: XCTestCase {
    func testReadingKeepsVisibleTurnsUntilFollowingLatestAgain() {
        let first = SimpleCaption.latest(in: [section(0, .remote, "First", "第一段")], languagePair: .englishToSimplifiedChinese)
        let next = SimpleCaption.latest(in: [section(1, .mine, "Next", "下一段")], languagePair: .englishToSimplifiedChinese)
        var reading = SimpleCaptionReading()
        reading.hold(first)
        reading.hold(next)
        XCTAssertEqual(reading.heldCaptions, first)
        reading.followLatest()
        XCTAssertNil(reading.heldCaptions)
        reading.hold(next)
        XCTAssertEqual(reading.heldCaptions, next)
    }

    func testDifferentLanguagesNeverDisplaySourceWhileWaitingOrFailing() throws {
        for pair in [MeetingLanguagePair.englishToSimplifiedChinese, .simplifiedChineseToEnglish] {
            for state in [TranslationState.pending, .translating, .failed] {
                var section = Section(id: 0, speaker: .remote)
                section.interimSource = "Private source content"
                section.translationState = state
                let row = try XCTUnwrap(SimpleCaption.latest(in: [section], languagePair: pair).first)
                XCTAssertEqual(row.text, "")
                XCTAssertEqual(row.translationState, state)
            }
        }
    }

    func testProgressiveTranslationRemainsVisibleDuringUpdatesAndFailure() throws {
        var section = Section(id: 0, speaker: .remote)
        section.interimSource = "The updated source"
        section.targetText = "  更新的译文  "
        for state in [TranslationState.translating, .done, .failed] {
            section.translationState = state
            let row = try XCTUnwrap(SimpleCaption.latest(in: [section], languagePair: .englishToSimplifiedChinese).first)
            XCTAssertEqual(row.text, "更新的译文")
            XCTAssertEqual(row.translationState, state)
        }
    }

    func testLatestTwoNonemptyTurnsPreserveChronologyAndBothSpeakers() {
        let sections = [
            section(1, .remote, "First", "第一段"),
            section(2, .mine, "Reply", "回复"),
            section(3, .remote, "Continuation", "继续"),
            Section(id: 4, speaker: .mine)
        ]
        let rows = SimpleCaption.latest(in: sections, languagePair: .englishToSimplifiedChinese)
        XCTAssertEqual(rows.map(\.id), [2, 3])
        XCTAssertEqual(rows.map(\.speaker), [.mine, .remote])
        XCTAssertEqual(rows.map(\.text), ["回复", "继续"])
    }

    func testSameLanguageUsesCurrentInterimEvenWhenNativeSnapshotLags() throws {
        for pair in [MeetingLanguagePair.englishToEnglish, .simplifiedChineseToSimplifiedChinese] {
            var value = section(0, .mine, "First sentence.", "Older snapshot")
            value.interimSource = "A growing sentence"
            value.translationState = .pending
            let row = try XCTUnwrap(SimpleCaption.latest(in: [value], languagePair: pair).first)
            XCTAssertEqual(row.text, "First sentence. A growing sentence")
            XCTAssertEqual(row.translationState, .done)
        }
    }

    func testEmptyAndLongContent() throws {
        XCTAssertTrue(SimpleCaption.latest(in: [], languagePair: .englishToSimplifiedChinese).isEmpty)
        let long = String(repeating: "Long readable translation. ", count: 100)
        let value = section(0, .remote, "Original", long)
        XCTAssertEqual(try XCTUnwrap(SimpleCaption.latest(in: [value], languagePair: .englishToSimplifiedChinese).first).text,
            long.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func section(_ id: Int, _ speaker: Speaker, _ source: String, _ target: String) -> Section {
        var value = Section(id: id, speaker: speaker)
        value.committedSource = [source]
        value.targetText = target
        value.translationState = .done
        return value
    }
}
