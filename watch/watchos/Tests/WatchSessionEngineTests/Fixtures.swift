//
//  Fixtures.swift
//  WatchSessionEngineTests
//
//  Reads the shared protocol fixtures and schemas straight from the repository.
//
//  Nothing is copied or bundled: the native watch client and the Flutter client
//  are held to the same files, and a drift in either one fails here first.
//

import Foundation
import WatchSessionEngine

enum Fixtures {
    /// Repository root, derived from this file's own path so `swift test` works
    /// from any working directory.
    static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static var protocolRoot: URL {
        repositoryRoot.appendingPathComponent("watch/sync_protocol")
    }

    static var sourcesRoot: URL {
        repositoryRoot.appendingPathComponent("watch/watchos/Sources/WatchSessionEngine")
    }

    /// The stepping, terminology and effort-kind values both watch clients
    /// share. Not part of the wire protocol — `watch/contract/` is where the
    /// two clients' agreements live.
    static func loggingContract() throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent(
            "watch/contract/watch_logging_contract.json"
        )
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed("watch/contract/watch_logging_contract.json")
        }
        return object
    }

    /// The sensor vocabulary both watch clients share: the sample kinds, the
    /// modality → platform workout type table, and the capability profile the
    /// GPS decision is derived from.
    static func sensorContract() throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent(
            "watch/contract/watch_sensor_contract.json"
        )
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed("watch/contract/watch_sensor_contract.json")
        }
        return object
    }

    /// F-CAP: one wrist session end to end — the events the wrist must emit and
    /// what the phone must hold after importing them — in three cases, shared by
    /// both stacks.
    static func captureContract() throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent(
            "watch/contract/watch_capture_contract.json"
        )
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed("watch/contract/watch_capture_contract.json")
        }
        return object
    }

    /// The session effort rating as both devices ask for it: the question, the
    /// scale, its end labels, and whether a never-synced wrist asks at all.
    static func effortRatingContract() throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent(
            "watch/contract/watch_effort_rating_contract.json"
        )
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed("watch/contract/watch_effort_rating_contract.json")
        }
        return object
    }

    /// The rest ping both watch clients owe a rest, as one table of polls and
    /// taps keyed by scenario.
    static func restPingContract() throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent(
            "watch/contract/watch_rest_ping_contract.json"
        )
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed("watch/contract/watch_rest_ping_contract.json")
        }
        return object
    }

    static func json(_ relativePath: String) throws -> [String: Any] {
        let url = protocolRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed(relativePath)
        }
        return object
    }

    static var manifest: [String: Any] {
        get throws { try json("fixtures/manifest.json") }
    }

    static func entries(_ key: String) throws -> [[String: Any]] {
        (try manifest[key] as? [[String: Any]]) ?? []
    }

    /// Every schema document, keyed the way `$ref` addresses it — relative to
    /// `watch/sync_protocol/schemas/`.
    static func schemaDocuments() throws -> [String: [String: Any]] {
        let root = protocolRoot.appendingPathComponent("schemas")
        let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )

        var documents: [String: [String: Any]] = [:]
        while let file = walker?.nextObject() as? URL {
            guard file.pathExtension == "json" else { continue }
            let key = String(file.path.dropFirst(root.path.count + 1))
            let data = try Data(contentsOf: file)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FixtureError.malformed(key)
            }
            documents[key] = object
        }
        return documents
    }

    enum FixtureError: Error {
        case malformed(String)
    }
}
