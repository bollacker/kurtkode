import Foundation
import Testing
@testable import AgentCore

struct BugHuntAppKeysTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func aKeyPressRightAfterACardAppearsDoesNotAnswerIt() {
        // A double ⌘↩: the second press lands on the next card in the same spot.
        #expect(!CardKeys.accepts(.key(isRepeat: false), appearedAt: t0, now: t0.addingTimeInterval(0.2)))
        #expect(CardKeys.accepts(.key(isRepeat: false), appearedAt: t0, now: t0.addingTimeInterval(0.5)))
    }

    @Test func aHeldKeyNeverAnswers() {
        #expect(!CardKeys.accepts(.key(isRepeat: true), appearedAt: t0, now: t0.addingTimeInterval(30)))
    }

    @Test func aSingleClickAnswersAtOnceButADoubleClicksSecondDoesNot() {
        #expect(CardKeys.accepts(.mouse(clickCount: 1), appearedAt: t0, now: t0.addingTimeInterval(0.05)))
        #expect(!CardKeys.accepts(.mouse(clickCount: 2), appearedAt: t0, now: t0.addingTimeInterval(0.05)))
        #expect(CardKeys.accepts(.mouse(clickCount: 2), appearedAt: t0, now: t0.addingTimeInterval(0.6)))
        #expect(!CardKeys.accepts(.other, appearedAt: t0, now: t0))
        #expect(CardKeys.accepts(.other, appearedAt: t0, now: t0.addingTimeInterval(0.5)))
    }

    @Test func cardShortcutsStayOutOfOtherFields() {
        #expect(CardKeys.shortcutActive(.confirm, focus: .none))
        #expect(CardKeys.shortcutActive(.dismiss, focus: .none))
        // ⌘↩ in the composer sends; Escape there still denies.
        #expect(!CardKeys.shortcutActive(.confirm, focus: .composer))
        #expect(CardKeys.shortcutActive(.dismiss, focus: .composer))
        // Escape in the sidebar search clears the search, not the card.
        #expect(!CardKeys.shortcutActive(.confirm, focus: .otherField))
        #expect(!CardKeys.shortcutActive(.dismiss, focus: .otherField))
        #expect(CardKeys.shortcutActive(.confirm, focus: .otherField, inCard: true))
    }

    @Test func escapeInAnotherFieldDoesNotStopTheRun() {
        #expect(!CardKeys.escapeStopsRun(focus: .otherField))
        #expect(CardKeys.escapeStopsRun(focus: .none))
        #expect(CardKeys.escapeStopsRun(focus: .composer))
    }

    @Test func oneCardAtATimeAndTheShownOneStays() {
        #expect(CardKeys.shown(current: nil, waiting: []) == nil)
        #expect(CardKeys.shown(current: nil, waiting: [.plan, .approval]) == .approval)
        // A question on screen isn't replaced by an approval arriving after it.
        #expect(CardKeys.shown(current: .question, waiting: [.question, .approval]) == .question)
        #expect(CardKeys.shown(current: .question, waiting: [.approval, .plan]) == .approval)
    }
}
