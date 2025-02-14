//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class SecureValueRecovery2Tests: XCTestCase {

    private var db: MockDB!
    private var svr: SecureValueRecovery2Impl!

    private var credentialStorage: SVRAuthCredentialStorageMock!
    private var scheduler: TestScheduler!

    override func setUp() {
        self.db = MockDB()
        self.credentialStorage = SVRAuthCredentialStorageMock()
        self.scheduler = TestScheduler()
        // Start the scheduler so everything executes synchronously.
        self.scheduler.start()
        self.svr = SecureValueRecovery2Impl(
            credentialStorage: credentialStorage,
            db: db,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            schedulers: TestSchedulers(scheduler: scheduler),
            storageServiceManager: FakeStorageServiceManager(),
            syncManager: OWSMockSyncManager(),
            tsAccountManager: SVR.TestMocks.TSAccountManager(),
            twoFAManager: SVR.TestMocks.OWS2FAManager()
        )
    }

    func testPinHashingNumeric() throws {
        let pin = "1234"
        let normalizedPin = SVRUtil.normalizePin(pin)
        XCTAssertEqual(pin, normalizedPin)

        let encodedString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)
        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: encodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: encodedString))

        // Test that pin hashes generated by argon2 are compatible with our current
        // verification strategy; we store these hashes to disk for verification,
        // so future verification needs to be backwards compatible.
        // Note that we don't need _new_ verification strings to be equivalent to old ones,
        // as long as both pass verification.
        let argon2EncodedString = "$argon2i$v=19$m=512,t=64,p=1$CxIHZ5tsrelHqqMfW7AsZw$4v19z1zecfP1hZ4b8RG1RFv6XDgU3BAEXME01r+xIBA"
        // This string was generated using:
        // let (_, encodedString) = try Argon2.hash(
        //    iterations: 64,
        //    memoryInKiB: 512,
        //    threads: 1,
        //    password: normalizedPin.data(using: .utf8)!,
        //    // Generated using `Cryptography.generateRandomBytes(SVRUtil.Constants.pinSaltLengthBytes)`
        //    salt: Data([11, 18, 7, 103, 155, 108, 173, 233, 71, 170, 163, 31, 91, 176, 44, 103]),
        //    desiredLength: 32,
        //    variant: .i,
        //    version: .v13
        // )

        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: argon2EncodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: argon2EncodedString))
    }

    func testPinHashingAlphaNumeric() throws {
        let pin = " LukeIAmYourFather123\n"
        let normalizedPin = SVRUtil.normalizePin(pin)
        XCTAssertEqual("LukeIAmYourFather123", normalizedPin)

        let encodedString = try SVRUtil.deriveEncodedPINVerificationString(pin: pin)
        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: encodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: encodedString))

        // Test that pin hashes generated by argon2 are compatible with our current
        // verification strategy; we store these hashes to disk for verification,
        // so future verification needs to be backwards compatible.
        // Note that we don't need _new_ verification strings to be equivalent to old ones,
        // as long as both pass verification.
        let argon2EncodedString = "$argon2i$v=19$m=512,t=64,p=1$CxIHZ5tsrelHqqMfW7AsZw$OgeedfJVzRTOUJ9CqeJ0e5ENGwfYiGyGj7/ejVrLOnw"
        // This string was generated using:
        // let (_, encodedString) = try Argon2.hash(
        //    iterations: 64,
        //    memoryInKiB: 512,
        //    threads: 1,
        //    password: normalizedPin.data(using: .utf8)!,
        //    // Generated using `Cryptography.generateRandomBytes(SVRUtil.Constants.pinSaltLengthBytes)`
        //    salt: Data([11, 18, 7, 103, 155, 108, 173, 233, 71, 170, 163, 31, 91, 176, 44, 103]),
        //    desiredLength: 32,
        //    variant: .i,
        //    version: .v13
        // )

        XCTAssert(SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: argon2EncodedString))
        // Some other password should fail to verify.
        XCTAssertFalse(SVRUtil.verifyPIN(pin: "notAPassword", againstEncodedPINVerificationString: argon2EncodedString))
    }
}
