//
//  ParseServer.swift
//  
//
//  Created by Corey Baker on 1/25/23.
//

import Vapor
import ParseSwift

// MARK: - In-memory primitive store

/// Replaces Parse-Swift's default keychain store with a plain in-memory
/// dictionary. This prevents macOS from ever showing a
/// "… wants to access key in your keychain" dialog when the server binary
/// is rebuilt (recompiling changes the binary identity, which invalidates
/// any previous "Always Allow" grant).
///
/// State is lost on process restart — intentional for a server-side app
/// that has no need for persistent local sessions.
///
/// Date encoding/decoding mirrors ParseCoding's internal strategies so that
/// Parse-Swift can round-trip its own stored values without errors.
private struct ParseServerMemoryStore: ParsePrimitiveStorable {

    private enum DateKey: String, CodingKey {
        case type = "__type"
        case iso
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f
    }()

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.container(keyedBy: DateKey.self)
            try c.encode("Date", forKey: .type)
            try c.encode(dateFormatter.string(from: date), forKey: .iso)
        }
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec -> Date in
            // Parse-Swift stores dates as plain ISO strings or {"__type":"Date","iso":"…"}
            if let str = try? dec.singleValueContainer().decode(String.self),
               let date = dateFormatter.date(from: str) {
                return date
            }
            let c = try dec.container(keyedBy: DateKey.self)
            guard let str = try c.decodeIfPresent(String.self, forKey: .iso),
                  let date = dateFormatter.date(from: str) else {
                throw ParseError(code: .otherCause, message: "Invalid date format in memory store")
            }
            return date
        }
        return d
    }

    private let lock = NSLock()
    private var _storage = [String: Data]()

    private var storage: [String: Data] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _storage = newValue
        }
    }

    mutating func delete(valueFor key: String) async throws {
        storage[key] = nil
    }

    mutating func deleteAll() async throws {
        storage = [:]
    }

    func get<T: Decodable>(valueFor key: String) async throws -> T? {
        guard let data = storage[key] else { return nil }
        return try Self.decoder.decode(T.self, from: data)
    }

    mutating func set<T: Encodable>(_ object: T, for key: String) async throws {
        storage[key] = try Self.encoder.encode(object)
    }
}

// MARK: Internal

internal struct Parse {
	nonisolated(unsafe) static var configuration: ParseServerConfiguration!
}

/// The current `ParseServerConfiguration` for ParseServerSwift.
public var configuration: ParseServerConfiguration {
    Parse.configuration
}

/**
 Configure `ParseServerSwift`. This should only be called once when starting your
 Vapor app. Typically in the `parseServerSwiftConfigure(_ app: Application)`.
 - parameter configuration: The ParseServer configuration.
 - parameter app: Core type representing a Vapor application.
 - throws: An error of `ParseError` type.
 - important: All custom configurations to your Vapor `app` server should occur before
 calling this method as it will modify and use the current configuration to understand the local
 server URL.
 - warning: Be sure to call this method before calling `try routes(app)`.
 */
public func initialize(
    _ configuration: ParseServerConfiguration,
    app: Application
) async throws {
    try await initializeServer(configuration, app: app)
}

func initialize(
    _ configuration: ParseServerConfiguration,
    app: Application,
    testing: Bool
) async throws {
    var configuration = configuration
    configuration.isTesting = testing
    try await initialize(configuration, app: app)
}

func initializeServer(
    _ configuration: ParseServerConfiguration,
    app: Application
) async throws {

    // Parse uses tailored encoders/decoders. These can be retrieved from any ParseObject
    ContentConfiguration.global.use(encoder: User.getEncoder(), for: .json)
    ContentConfiguration.global.use(decoder: User.getDecoder(), for: .json)

    guard let parseServerURL = URL(string: configuration.primaryParseServerURLString) else {
        let error = ParseError(
            code: .otherCause,
            message: "Could not make a URL from the Parse Server string"
        )
        throw error
    }

    if !configuration.isTesting {
        try setConfiguration(configuration)
        do {
            // Initialize the Parse-Swift SDK. Add any additional parameters you need
            try await ParseSwift.initialize(
                applicationId: configuration.applicationId,
                primaryKey: configuration.primaryKey,
                maintenanceKey: configuration.maintenanceKey,
                serverURL: parseServerURL,
                // POST all queries instead of using GET.
                usingPostForQuery: true,
                // Use in-memory storage — prevents macOS Keychain prompts caused
                // by the binary identity changing on every `swift run` recompile.
                primitiveStore: ParseServerMemoryStore(),
                // Do not use cache for anything.
                requestCachePolicy: .reloadIgnoringLocalCacheData
            ) { _, completionHandler in
                // Setup to use default certificate pinning. See Parse-Swift docs for more info
                completionHandler(.performDefaultHandling, nil)
            }
            // Check the health of all Parse-Server
            try await checkServerHealth()
        } catch {
            await deleteHooks(app)
            try await app.asyncShutdown()
        }
    } else {
        Parse.configuration = configuration
    }
}
