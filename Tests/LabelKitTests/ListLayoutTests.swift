//
//  ListLayoutTests.swift
//  LabelKitTests
//

import Testing
@testable import LabelKit

@Suite("ListLayout")
struct ListLayoutTests {

    private var environment: ZPLEnvironment {
        ZPLEnvironment(stock: Stock.Preset.label4x, device: Device.Preset.ZD620)
    }

    @Test func itemUsesItemFontAndIndentAtFirstBaseline() throws {
        let zpl = try ListLayout().makeLabel([.item("eggs")], environment: environment).zpl()
        // topMargin 20 + itemFontSize 50 + gap 20 = 90
        #expect(zpl.contains("^A0N,50,50^FO100,90^FDeggs^FS"))
    }

    @Test func headerUsesHeaderFontAndSmallerIndent() throws {
        let zpl = try ListLayout().makeLabel([.header("Costco:")], environment: environment).zpl()
        // topMargin 20 + headerFontSize 60 + gap 20 = 100
        #expect(zpl.contains("^A0N,60,60^FO60,100^FDCostco:^FS"))
    }

    @Test func blankAdvancesHalfAnItemPitchAndEmitsNothing() throws {
        let zpl = try ListLayout()
            .makeLabel([.item("a"), .blank, .item("b")], environment: environment).zpl()
        // a at 90; blank adds (50+20)/2 = 35 -> 125; b adds 70 -> 195
        #expect(zpl.contains("^FO100,90^FDa^FS"))
        #expect(zpl.contains("^FO100,195^FDb^FS"))
    }

    @Test func labelLengthIsLastBaselinePlusBottomMargin() throws {
        let zpl = try ListLayout().makeLabel([.item("only")], environment: environment).zpl()
        #expect(zpl.contains("^LL408"))   // 90 + 318
    }

    @Test func emptyInputStillProducesAWellFormedLabel() throws {
        let zpl = try ListLayout().makeLabel([], environment: environment).zpl()
        #expect(zpl.hasPrefix("^XA"))
        #expect(zpl.hasSuffix("^XZ"))
        #expect(zpl.contains("^LL338"))   // topMargin 20 + 318
    }

    @Test func commandIntroducersAreStrippedFromText() throws {
        let zpl = try ListLayout()
            .makeLabel([.item("bad^XZand~JAmore")], environment: environment).zpl()
        #expect(zpl.contains("^FDbadXZandJAmore^FS"))
        // Exactly one ^XZ: the label terminator, not one smuggled in via text.
        #expect(zpl.components(separatedBy: "^XZ").count - 1 == 1)
    }

    @Test func computedLengthIsPublishedOnTheEnvironmentGeometry() throws {
        let label = ListLayout().makeLabel([.item("only")], environment: environment)
        #expect(label.environment.options.geometry.heightDots == 408)
    }

    @Test func styleOverridesAreHonored() throws {
        var layout = ListLayout()
        layout.itemFontSize = 30
        layout.gap = 10
        layout.itemIndent = 40
        let zpl = try layout.makeLabel([.item("small")], environment: environment).zpl()
        #expect(zpl.contains("^A0N,30,30^FO40,60^FDsmall^FS"))   // 20 + 30 + 10
    }
}
