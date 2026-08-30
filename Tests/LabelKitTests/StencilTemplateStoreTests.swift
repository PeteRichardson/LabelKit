//
//  StencilTemplateStoreTests.swift
//  LabelKitTests
//

import Foundation
import Testing
@testable import LabelKit

@Suite("StencilTemplateStore file-URL initializer")
struct StencilTemplateStoreTests {

    @Test func loadsTemplatesFromAnExplicitFileURL() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("labelkit-store-\(UUID().uuidString).json")
        let json = #"{"version":1,"templates":{"greeting":"^XA^FD{{ who }}^FS^XZ"}}"#
        try Data(json.utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = StencilTemplateStore(fileURL: tmp)
        try store.load()

        #expect(try store.render(name: "greeting", context: ["who": "world"])
                == "^XA^FDworld^FS^XZ")
    }

    @Test func missingFileLeavesTheStoreEmptyRatherThanThrowing() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("labelkit-absent-\(UUID().uuidString).json")

        let store = StencilTemplateStore(fileURL: missing)
        try store.load()   // documented no-op when the file is absent

        #expect(store.listNames().isEmpty)
    }
}
