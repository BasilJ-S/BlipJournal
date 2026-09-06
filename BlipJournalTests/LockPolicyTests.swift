import Foundation
import Testing
@testable import BlipJournal

struct LockPolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func nilBackgroundTimeNeverLocks() {
        #expect(LockPolicy().shouldLock(backgroundedAt: nil, now: now) == false)
    }

    @Test func withinGraceDoesNotLock() {
        let policy = LockPolicy()
        #expect(policy.shouldLock(backgroundedAt: now.addingTimeInterval(-29), now: now) == false)
    }

    @Test func atGraceLocks() {
        let policy = LockPolicy()
        #expect(policy.shouldLock(backgroundedAt: now.addingTimeInterval(-30), now: now) == true)
    }

    @Test func customGracePeriodIsHonoured() {
        let policy = LockPolicy(gracePeriod: 300)
        #expect(policy.shouldLock(backgroundedAt: now.addingTimeInterval(-299), now: now) == false)
        #expect(policy.shouldLock(backgroundedAt: now.addingTimeInterval(-300), now: now) == true)
    }
}
