import XCTest
@testable import 同频

final class MeetingLanguageTests: XCTestCase {
    func testLanguageNamesAndPlatformIdentifiersAreFixed() {
        XCTAssertEqual(MeetingLanguage.english.label, "英语")
        XCTAssertEqual(MeetingLanguage.english.localeID, "en-US")
        XCTAssertEqual(MeetingLanguage.english.translationIdentifier, "en")
        XCTAssertEqual(MeetingLanguage.simplifiedChinese.label, "简体中文")
        XCTAssertEqual(MeetingLanguage.simplifiedChinese.localeID, "zh-CN")
        XCTAssertEqual(MeetingLanguage.simplifiedChinese.translationIdentifier, "zh-Hans")
    }

    func testPairPreservesEverySourceAndTargetCombination() {
        let languages = MeetingLanguage.allCases

        for source in languages {
            for target in languages {
                let pair = MeetingLanguagePair(source: source, target: target)
                XCTAssertEqual(pair.source, source)
                XCTAssertEqual(pair.target, target)
            }
        }
    }

    func testTranslationIsNeededOnlyWhenLanguagesDiffer() {
        XCTAssertFalse(MeetingLanguagePair.englishToEnglish.needsTranslation)
        XCTAssertTrue(MeetingLanguagePair.englishToSimplifiedChinese.needsTranslation)
        XCTAssertTrue(MeetingLanguagePair.simplifiedChineseToEnglish.needsTranslation)
        XCTAssertFalse(MeetingLanguagePair.simplifiedChineseToSimplifiedChinese.needsTranslation)
    }

    func testEveryPairHasDistinctStablePersistenceValue() {
        let pairs: [MeetingLanguagePair] = [
            .englishToEnglish,
            .englishToSimplifiedChinese,
            .simplifiedChineseToEnglish,
            .simplifiedChineseToSimplifiedChinese
        ]

        XCTAssertEqual(Set(pairs.map(\.rawValue)).count, pairs.count)
        XCTAssertEqual(MeetingLanguagePair.englishToSimplifiedChinese.rawValue, "english")
        XCTAssertEqual(MeetingLanguagePair.simplifiedChineseToSimplifiedChinese.rawValue, "chinese")
    }
}
