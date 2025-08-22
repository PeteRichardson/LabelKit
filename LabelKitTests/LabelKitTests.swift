//
//  LabelKitTests.swift
//  LabelKitTests
//
//  Created by Peter Richardson on 8/22/25.
//

import Testing
@testable import LabelKit

struct LabelKitTests {

    @Test func test_positive() async throws {
        #expect(add(x: 4, y: 7) == 11)
    }

}
