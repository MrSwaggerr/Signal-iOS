//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum SVR {

    static let masterKeyLengthBytes: UInt = 32

    public enum SVRError: Error, Equatable {
        case assertion
        case invalidPin(remainingAttempts: UInt32)
        case backupMissing
    }

    public enum PinType: Int {
        case numeric = 1
        case alphanumeric = 2

        public init(forPin pin: String) {
            let normalizedPin = SVRUtil.normalizePin(pin)
            self = normalizedPin.digitsOnly() == normalizedPin ? .numeric : .alphanumeric
        }
    }

    public enum DerivedKey: Hashable {
        /// The key required to bypass reglock and register or change number
        /// into an owned account.
        case registrationLock
        /// The key required to bypass sms verification when registering for an account.
        /// Independent from reglock; if reglock is present it is _also_ required, if not
        /// this token is still required.
        case registrationRecoveryPassword
        case storageService

        case storageServiceManifest(version: UInt64)
        case storageServiceRecord(identifier: StorageService.StorageIdentifier)

        var rawValue: String {
            switch self {
            case .registrationLock:
                return "Registration Lock"
            case .registrationRecoveryPassword:
                return "Registration Recovery"
            case .storageService:
                return "Storage Service Encryption"
            case .storageServiceManifest(let version):
                return "Manifest_\(version)"
            case .storageServiceRecord(let identifier):
                return "Item_\(identifier.data.base64EncodedString())"
            }
        }

        public func derivedData(from dataToDeriveFrom: Data) -> Data? {
            guard let data = rawValue.data(using: .utf8) else {
                owsFailDebug("Failed to encode data")
                return nil
            }

            return Cryptography.computeSHA256HMAC(data, key: dataToDeriveFrom)
        }
    }

    /// An auth credential is needed to talk to the SVR server.
    /// This defines how we should get that auth credential
    public indirect enum AuthMethod: Equatable {
        /// Explicitly provide an auth credential to use directly with SVR.
        /// note: if it fails, will fall back to the backup or implicit if unset.
        case svrAuth(SVRAuthCredential, backup: AuthMethod?)
        /// Get an SVR auth credential from the chat server first with the
        /// provided credentials, then use it to talk to the SVR server.
        case chatServerAuth(AuthedAccount)
        /// Use whatever SVR auth credential we have cached; if unavailable or
        /// if invalid, falls back to getting a SVR auth credential from the chat server
        /// with the chat server auth credentials we have cached.
        case implicit
    }

    public enum RestoreKeysResult {
        case success
        case invalidPin(remainingAttempts: UInt32)
        // This could mean there was never a backup, or it's been
        // deleted due to using up all pin attempts.
        case backupMissing
        case networkError(Error)
        // Some other issue.
        case genericError(Error)
    }

    public struct DerivedKeyData {
        /// Can never be empty data; instances would fail to initialize.
        public let rawData: Data
        public let type: DerivedKey

        internal init?(_ rawData: Data?, _ type: DerivedKey) {
            guard let rawData, !rawData.isEmpty else {
                return nil
            }
            self.rawData = rawData
            self.type = type
        }

        public var canonicalStringRepresentation: String {
            switch type {
            case .storageService, .storageServiceManifest, .storageServiceRecord, .registrationRecoveryPassword:
                return rawData.base64EncodedString()
            case .registrationLock:
                return rawData.hexadecimalString
            }
        }
    }

    public enum ApplyDerivedKeyResult {
        case success(Data)
        case masterKeyMissing
        //  Error encrypting or decrypting
        case cryptographyError(Error)
    }
}

public protocol SecureValueRecovery {

    /// Indicates whether or not we have a master key locally
    func hasMasterKey(transaction: DBReadTransaction) -> Bool

    /// Indicates whether or not we have a master key stored in SVR
    func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool

    /// The pin type used (e.g. numeric, alphanumeric)
    func currentPinType(transaction: DBReadTransaction) -> SVR.PinType?

    /// Indicates whether your pin is valid when compared to your stored keys.
    /// This is a local verification and does not make any requests to the SVR.
    /// Callback will happen on the main thread.
    func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void)

    // When changing number, we need to verify the PIN against the new number's SVR
    // record in order to generate a registration lock token. It's important that this
    // happens without touching any of the state we maintain around our account.
    func acquireRegistrationLockForNewNumber(with pin: String, and auth: SVRAuthCredential) -> Promise<String>

    /// Loads the users key, if any, from the SVR into the database.
    func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>

    /// Backs up the user's master key to SVR and stores it locally in the database.
    /// If the user doesn't have a master key already a new one is generated.
    func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod, rotateMasterKey: Bool) -> Promise<Void>

    /// Remove the keys locally from the device and from the SVR,
    /// they will not be able to be restored.
    func deleteKeys() -> Promise<Void>

    // MARK: - Master Key Encryption

    func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult

    func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult

    func warmCaches()

    /// Removes the SVR keys locally from the device, they can still be
    /// restored from the server if you know the pin.
    func clearKeys(transaction: DBWriteTransaction)

    func storeSyncedStorageServiceKey(
        data: Data?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    )

    func setMasterKeyBackedUp(_ value: Bool, transaction: DBWriteTransaction)

    /// Rotate the master key and _don't_ back it up to the SVR server, in effect switching to a
    /// local-only master key and disabling PIN usage for backup restoration.
    func useDeviceLocalMasterKey(authedAccount: AuthedAccount, transaction: DBWriteTransaction)

    func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> SVR.DerivedKeyData?

    func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool
}
