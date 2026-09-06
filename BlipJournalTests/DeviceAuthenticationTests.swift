import Foundation
import LocalAuthentication
import Testing
@testable import OpenBlip

struct DeviceAuthenticationTests {
    @Test func onlyMissingPasscodePermitsContinuingWithoutAuthentication() {
        #expect(DeviceAuthentication.hasNoPasscode(
            NSError(domain: LAError.errorDomain, code: LAError.passcodeNotSet.rawValue)))
        for code in [LAError.invalidContext, .notInteractive, .authenticationFailed, .biometryLockout] {
            #expect(!DeviceAuthentication.hasNoPasscode(
                NSError(domain: LAError.errorDomain, code: code.rawValue)))
        }
        #expect(!DeviceAuthentication.hasNoPasscode(nil))
        #expect(!DeviceAuthentication.hasNoPasscode(
            NSError(domain: NSCocoaErrorDomain, code: LAError.passcodeNotSet.rawValue)))
    }
}
