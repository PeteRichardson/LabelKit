//
//  TemplateArchive.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//


import Foundation
import Stencil

struct TemplateArchive: Codable {
    var version: Int = 1
    var templates: [String: String] = [:]
}

public final class StencilTemplateStore: Loader {
    private let queue = DispatchQueue(label: "StencilTemplateStore.queue")
    private var archive = TemplateArchive()
    private(set) var fileURL: URL

    /// Designated initializer that ALWAYS prefers `preferredFolderName`.
    /// If the target JSON doesn't exist yet, we'll search `legacyFolderNames` and migrate the first one we find.
    public init() throws {
        let file = try SharedStore.templatesURL()
        self.fileURL = file
    }

    /// Initializes a store backed by an explicit file, bypassing the
    /// Application Support / group-container search performed by `init()`.
    ///
    /// Used by examples and snippets so they read templates checked into the
    /// repository and run on a fresh clone with no user state. Apps that want
    /// the user's own template store should keep using `init()`.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private static func findFirstExistingJSON(
        filename: String,
        folderNames: [String],
        under appSupport: URL,
        fm: FileManager
    ) -> (URL, String)? {
        for name in folderNames {
            let folder = appSupport.appendingPathComponent(name, isDirectory: true)
            let file = folder.appendingPathComponent(filename)
            if fm.fileExists(atPath: file.path) {
                return (file, name)
            }
        }
        return nil
    }

    // MARK: Persistence

    public func load() throws {
        try queue.sync {
            let fm = FileManager.default
            guard fm.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            self.archive = try JSONDecoder().decode(TemplateArchive.self, from: data)
        }
    }

    public func save(pretty: Bool = true) throws {
        try queue.sync {
            let encoder = JSONEncoder()
            if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
            let data = try encoder.encode(self.archive)

            let tmp = fileURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .noFileProtection)

            let fm = FileManager.default
            if fm.fileExists(atPath: fileURL.path) {
                _ = try fm.replaceItemAt(fileURL, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: fileURL)
            }
        }
    }

    // MARK: CRUD

    func listNames() -> [String] { queue.sync { Array(archive.templates.keys).sorted() } }

    subscript(name: String) -> String? {
        get { queue.sync { archive.templates[name] } }
        set {
            queue.sync {
                if let v = newValue { archive.templates[name] = v }
                else { archive.templates.removeValue(forKey: name) }
            }
        }
    }

    // MARK: Stencil.Loader

    public func loadTemplate(name: String, environment: Environment) throws -> Template {
        guard let t = queue.sync(execute: { archive.templates[name] }) else {
//            throw TemplateDoesNotExist(templateNames: [name], loader: self, environment: environment)
            throw TemplateDoesNotExist(templateNames: [name], loader: self)
        }
        return Template(templateString: t)
    }

    public func loadTemplateNames() -> [String] { listNames() }

    // MARK: Convenience

    public func makeEnvironment(extensions: [Extension] = []) -> Environment {
        let ext = Extension()
        return Environment(loader: self, extensions: [ext])
    }

    public func render(name: String, context: [String: Any] = [:]) throws -> String {
        try makeEnvironment().renderTemplate(name: name, context: context)
    }

    public func renderZPL(_ zpl: String, context: [String: Any] = [:]) throws -> String {
        // Create a unique temporary template name
        let tempName = "__tmp_" + UUID().uuidString

        // Insert the raw ZPL as a template under the temporary name
        queue.sync { archive.templates[tempName] = zpl }

        // Always remove the temporary template, even if rendering throws
        defer {
            _ = queue.sync { archive.templates.removeValue(forKey: tempName) }
        }

        // Reuse the existing rendering pipeline so recursive includes work
        let result = try render(name: tempName, context: context)
        return result
    }
}


enum SharedStore {
    /// Your App Group ID
    static let groupID = "group.com.peterichardson.labelkit"

    /// Path inside the group container where you keep app-support data
    static let relativeSupportPath = "Library/Application Support/LabelKit"

    /// URL for the shared Application Support folder, creating it if needed.
    static func appSupportURL() throws -> URL {
        // 1) Try App Group container (preferred)
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) {
            let support = groupURL.appendingPathComponent(relativeSupportPath, isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            return support
        }

        // 2) Fallbacks (for non-entitled callers):
        //    - If the process is non-sandboxed CLI, we can still address the group container by path.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let manualGroup = home
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(groupID, isDirectory: true)
            .appendingPathComponent(relativeSupportPath, isDirectory: true)

        try FileManager.default.createDirectory(at: manualGroup, withIntermediateDirectories: true)
        return manualGroup
    }

    static func templatesURL() throws -> URL {
        try appSupportURL().appendingPathComponent("templates.json", isDirectory: false)
    }
}
