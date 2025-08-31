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
    private static let llMarker = "<<LL_MARKER>>"

    /// Designated initializer that ALWAYS prefers `preferredFolderName`.
    /// If the target JSON doesn't exist yet, we'll search `legacyFolderNames` and migrate the first one we find.
    public init(
        filename: String = "templates.json",
        preferredFolderName: String,
        legacyFolderNames: [String] = []  // e.g. [Bundle.main.bundleIdentifier, ProcessInfo.processName].compactMap { $0 }
    ) throws {
        let fm = FileManager.default

        // ~/Library/Application Support
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

        // Preferred target folder
        let preferredFolder = appSupport.appendingPathComponent(preferredFolderName, isDirectory: true)
        if !fm.fileExists(atPath: preferredFolder.path) {
            try fm.createDirectory(at: preferredFolder, withIntermediateDirectories: true)
        }
        let preferredFile = preferredFolder.appendingPathComponent(filename)

        // If preferred file missing, try to migrate from legacy locations
        if !fm.fileExists(atPath: preferredFile.path) {
            if let (legacyFile, _) = Self.findFirstExistingJSON(
                filename: filename,
                folderNames: legacyFolderNames,
                under: appSupport,
                fm: fm
            ) {
                // Copy (don’t move) to keep legacy intact, but you can switch to move if you prefer.
                try fm.copyItem(at: legacyFile, to: preferredFile)
            }
        }

        self.fileURL = preferredFile
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
        ext
            .registerTag("ll") {
                _,
                _ in return Self.llMarker as! any NodeType
            } // always outputs the marker
        return Environment(loader: self, extensions: [ext])
    }

    public func render(name: String, context: [String: Any] = [:]) throws -> String {
        try makeEnvironment().renderTemplate(name: name, context: context)
    }
}
