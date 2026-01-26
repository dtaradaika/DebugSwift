//
//  DebugSwift.Database.swift
//  DebugSwift
//
//  Database encryption configuration for SQLCipher support
//

import Foundation

/// Protocol for providing encryption keys for SQLCipher databases
public protocol DatabaseKeyProvider: Sendable {
    /// Returns the encryption key for the database
    /// - Returns: The encryption key as a String (passphrase) or nil if key is unavailable
    func provideKey() -> String?
}

/// A simple key provider that stores the key directly
public final class StaticDatabaseKeyProvider: DatabaseKeyProvider, @unchecked Sendable {
    private let key: String

    public init(key: String) {
        self.key = key
    }

    public func provideKey() -> String? {
        return key
    }
}

/// Database viewer UI mode
public enum DatabaseViewerMode: String, CaseIterable, Sendable {
    case classic = "classic"
    case modern = "modern"

    public var displayName: String {
        switch self {
        case .classic:
            return "Classic"
        case .modern:
            return "Modern (QA Enhanced)"
        }
    }

    public var description: String {
        switch self {
        case .classic:
            return "Traditional table-based view with basic functionality"
        case .modern:
            return "Enhanced grid view with filters, export, and QA tools"
        }
    }
}

extension DebugSwift {
    public final class Database: @unchecked Sendable {
        public static let shared = Database()

        private static let viewerModeKey = "DebugSwift.Database.ViewerMode"

        private init() {}

        // MARK: - Internal Storage

        private var encryptedDatabases: [EncryptedDatabaseConfig] = []
        private let lock = NSLock()

        // MARK: - Public API

        /// Register an encrypted database with a key provider
        /// - Parameters:
        ///   - name: Display name for the database
        ///   - path: Full path to the database file
        ///   - keyProvider: Provider that supplies the encryption key
        ///
        /// Example:
        /// ```swift
        /// // Using a static key provider
        /// let keyProvider = StaticDatabaseKeyProvider(key: "my-secret-key")
        /// DebugSwift.Database.shared.addEncrypted(
        ///     name: "Secure Database",
        ///     path: "/path/to/database.sqlite",
        ///     keyProvider: keyProvider
        /// )
        ///
        /// // Using a custom key provider
        /// class KeychainKeyProvider: DatabaseKeyProvider {
        ///     func provideKey() -> String? {
        ///         return KeychainManager.getKey(for: "database")
        ///     }
        /// }
        /// DebugSwift.Database.shared.addEncrypted(
        ///     name: "Keychain Protected DB",
        ///     path: databasePath,
        ///     keyProvider: KeychainKeyProvider()
        /// )
        /// ```
        public func addEncrypted(
            name: String,
            path: String,
            keyProvider: DatabaseKeyProvider
        ) {
            lock.lock()
            defer { lock.unlock() }

            // Remove existing registration for same path
            encryptedDatabases.removeAll { $0.path == path }

            let config = EncryptedDatabaseConfig(
                name: name,
                path: path,
                keyProvider: keyProvider
            )
            encryptedDatabases.append(config)
        }

        /// Register an encrypted database with a static key
        /// - Parameters:
        ///   - name: Display name for the database
        ///   - path: Full path to the database file
        ///   - key: The encryption key/passphrase
        ///
        /// Example:
        /// ```swift
        /// DebugSwift.Database.shared.addEncrypted(
        ///     name: "My Secure Database",
        ///     path: databasePath,
        ///     key: "my-secret-passphrase"
        /// )
        /// ```
        public func addEncrypted(
            name: String,
            path: String,
            key: String
        ) {
            addEncrypted(
                name: name,
                path: path,
                keyProvider: StaticDatabaseKeyProvider(key: key)
            )
        }

        /// Remove an encrypted database registration by path
        /// - Parameter path: Path of the database to remove
        public func removeEncrypted(path: String) {
            lock.lock()
            defer { lock.unlock() }

            encryptedDatabases.removeAll { $0.path == path }
        }

        /// Remove all encrypted database registrations
        public func removeAllEncrypted() {
            lock.lock()
            defer { lock.unlock() }

            encryptedDatabases.removeAll()
        }

        /// Get all registered encrypted database configurations
        /// - Returns: Array of registered encrypted database configs
        public func getEncryptedDatabases() -> [EncryptedDatabaseConfig] {
            lock.lock()
            defer { lock.unlock() }

            return encryptedDatabases
        }

        /// Check if a database at the given path is registered as encrypted
        /// - Parameter path: Path to check
        /// - Returns: True if the database is registered as encrypted
        public func isEncrypted(path: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            return encryptedDatabases.contains { $0.path == path }
        }

        /// Get the key for an encrypted database
        /// - Parameter path: Path of the database
        /// - Returns: The encryption key or nil if not registered or key unavailable
        internal func getKey(for path: String) -> String? {
            lock.lock()
            defer { lock.unlock() }

            guard let config = encryptedDatabases.first(where: { $0.path == path }) else {
                return nil
            }
            return config.keyProvider.provideKey()
        }

        // MARK: - Viewer Mode Settings

        /// Current database viewer UI mode
        public var viewerMode: DatabaseViewerMode {
            get {
                if let rawValue = UserDefaults.standard.string(forKey: Self.viewerModeKey),
                   let mode = DatabaseViewerMode(rawValue: rawValue) {
                    return mode
                }
                return .modern // Default to modern for better QA experience
            }
            set {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.viewerModeKey)
            }
        }

        /// Toggle between classic and modern viewer modes
        /// - Returns: The new viewer mode after toggle
        @discardableResult
        public func toggleViewerMode() -> DatabaseViewerMode {
            let newMode: DatabaseViewerMode = viewerMode == .classic ? .modern : .classic
            viewerMode = newMode
            return newMode
        }
    }
}

// MARK: - Supporting Types

/// Configuration for an encrypted database
public struct EncryptedDatabaseConfig: Sendable {
    public let name: String
    public let path: String
    public let keyProvider: DatabaseKeyProvider

    public init(name: String, path: String, keyProvider: DatabaseKeyProvider) {
        self.name = name
        self.path = path
        self.keyProvider = keyProvider
    }
}
