//
//  ParseServerConfiguration.swift
//  
//
//  Created by Corey Baker on 1/25/23.
//

import Vapor
import ParseSwift

/**
 The Configuration for ParseServerSwift.
 */
public struct ParseServerConfiguration {

    /// The application id for your Node.js Parse Server application.
    public internal(set) var applicationId: String

    /// The maintenance key for your Node.js Parse Server application.
    public internal(set) var maintenanceKey: String?

    /// The primary key for your Node.js Parse Server application.
    /// - note: This has been renamed from `masterKey` to reflect
    /// [inclusive language](https://github.com/dialpad/inclusive-language#motivation).
    public internal(set) var primaryKey: String

    /// The key used to authenticate incoming webhook calls from a Parse Server.
    public internal(set) var webhookKey: String?

    /// The primary Node.js Parse Server URL string.
    public internal(set) var primaryParseServerURLString: String

    /// All Node.js Parse Server URL strings.
    public internal(set) var parseServerURLStrings = [String]()

    /// The current address of ParseServerSwift.
    /// This is the URL webhooks are registered under, so it must be reachable
    /// by the Parse Server. Defaults to the bind address; behind a proxy or on
    /// a PaaS (where the bind address is internal), set
    /// **PARSE_SERVER_SWIFT_SERVER_URL** to the public URL instead.
    public internal(set) var serverPathname: String

    var hooks = Hooks()
    var isTesting = false
    var logger = Logger(label: "com.parse-server-swift")

    /**
     Create a configuration for `ParseServerSwift`.
     - parameter app: Core type representing a Vapor application.
     - parameter tlsConfiguration: Manages configuration of TLS for SwiftNIO programs.
     - throws: An error of `ParseError` type.
     - important: This initializer looks for environment variables that begin
     with **PARSE_SERVER_SWIFT** such as **PARSE_SERVER_SWIFT_APPLICATION_ID**,
      **PARSE_SERVER_SWIFT_MAINTENANCE_KEY**, and **PARSE_SERVER_SWIFT_PRIMARY_KEY**.
     */
    public init(
        app: Application,
        tlsConfiguration: TLSConfiguration? = nil
    ) throws {
        guard let applicationId = Environment.process.PARSE_SERVER_SWIFT_APPLICATION_ID,
                let primaryKey = Environment.process.PARSE_SERVER_SWIFT_PRIMARY_KEY else {
            throw ParseError(
                code: .otherCause,
                message: "Missing environment variables for applicationId or primaryKey"
            )
        }
        self.applicationId = applicationId
        self.maintenanceKey = Environment.process.PARSE_SERVER_SWIFT_MAINTENANCE_KEY
        self.primaryKey = primaryKey
        app.http.server.configuration.hostname = Environment.process.PARSE_SERVER_SWIFT_HOST_NAME ?? "localhost"
        app.http.server.configuration.port = Int(Environment.process.PARSE_SERVER_SWIFT_PORT ?? 8080)
        app.http.server.configuration.tlsConfiguration = tlsConfiguration
        // swiftlint:disable:next line_length
        app.routes.defaultMaxBodySize = ByteCount(stringLiteral: Environment.process.PARSE_SERVER_SWIFT_DEFAULT_MAX_BODY_SIZE ?? "16kb")

        serverPathname = try Self.resolveServerPathname(for: app)
        webhookKey = Environment.process.PARSE_SERVER_SWIFT_WEBHOOK_KEY

        let serverURLStrings = try getParseServerURLs()
        primaryParseServerURLString = serverURLStrings.0
        parseServerURLStrings.append(primaryParseServerURLString)
        parseServerURLStrings.append(contentsOf: serverURLStrings.1)
    }

    /**
     Create a configuration for `ParseServerSwift`.
     - parameter app: Core type representing a Vapor application.
     - parameter hostName: Host name the server will bind to.
     - parameter port: Port the server will bind to.
     - parameter tlsConfiguration: Manages configuration of
     TLS for SwiftNIO programs.
     - parameter maxBodySize: Default value used by
     `HTTPBodyStreamStrategy.collect` when `maxSize` is `nil`.
     - parameter applicationId:The application id for your Node.js Parse Server application.
     - parameter primaryKey: The primary key for your Node.js Parse Server application.
     - parameter maintenanceKey: The maintenance key for your Node.js Parse Server application.
     - parameter webhookKey: The key used to authenticate
     incoming webhook calls from a Parse Server. Defaults to **nil**.
     - parameter parseServerURLString: The Node.js Parse
     Server URL string such as http://parse:1337/parse. Only
     needs to be one server.
     - throws: An error of `ParseError` type.
     */
    public init(
        app: Application,
        hostName: String = "localhost",
        port: Int = 8080,
        tlsConfiguration: TLSConfiguration? = nil,
        maxBodySize: ByteCount = "16kb",
        applicationId: String,
        maintenanceKey: String? = nil,
        primaryKey: String,
        webhookKey: String? = nil,
        parseServerURLString: String
    ) throws {
        self.applicationId = applicationId
        self.maintenanceKey = maintenanceKey
        self.primaryKey = primaryKey
        self.webhookKey = webhookKey

        app.http.server.configuration.hostname = hostName
        app.http.server.configuration.port = port
        app.http.server.configuration.tlsConfiguration = tlsConfiguration
        app.routes.defaultMaxBodySize = maxBodySize
        serverPathname = try Self.resolveServerPathname(for: app)

        let serverURLStrings = try getParseServerURLs(parseServerURLString)
        primaryParseServerURLString = serverURLStrings.0
        parseServerURLStrings.append(primaryParseServerURLString)
        parseServerURLStrings.append(contentsOf: serverURLStrings.1)
    }

    /// The URL webhooks are registered under: **PARSE_SERVER_SWIFT_SERVER_URL**
    /// when set (validated — behind a proxy or on a PaaS the bind address is
    /// unreachable, and a malformed value would silently kill every hook
    /// registration), otherwise derived from the bind configuration.
    private static func resolveServerPathname(for app: Application) throws -> String {
        guard let advertised = Environment.process.PARSE_SERVER_SWIFT_SERVER_URL else {
            return buildServerURL(from: app.http.server.configuration)
        }
        let trimmed = advertised.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw ParseError(
                code: .otherCause,
                message: "PARSE_SERVER_SWIFT_SERVER_URL must be a full http(s) URL; got \"\(advertised)\""
            )
        }
        return trimmed
    }

}
