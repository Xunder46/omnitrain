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
