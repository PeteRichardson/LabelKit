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

    @Test func itemIsPlacedAtFirstBaselineUsingTheDefaultFont() throws {
        let zpl = try ListLayout().makeLabel([.item("eggs")], environment: environment).zpl()
        // topMargin 20 + itemFontSize 50 + gap 20 = 90
        #expect(zpl.contains("^FO100,90^FH^FDeggs^FS"))
    }

    @Test func headerUsesHeaderFontAndSmallerIndent() throws {
        let zpl = try ListLayout().makeLabel([.header("Costco:")], environment: environment).zpl()
        // topMargin 20 + headerFontSize 60 + gap 20 = 100
        #expect(zpl.contains("^A0N,60,60^FO60,100^FH^FDCostco:^FS"))
    }

    @Test func blankAdvancesHalfAnItemPitchAndEmitsNothing() throws {
        let zpl = try ListLayout()
            .makeLabel([.item("a"), .blank, .item("b")], environment: environment).zpl()
        // a at 90; blank adds (50+20)/2 = 35 -> 125; b adds 70 -> 195
        #expect(zpl.contains("^FO100,90^FH^FDa^FS"))
        #expect(zpl.contains("^FO100,195^FH^FDb^FS"))
    }

    // MARK: - Encoding and font declaration

    @Test func utf8EncodingIsDeclaredBeforeAnyFieldData() throws {
        let zpl = try ListLayout().makeLabel([.item("café piña")], environment: environment).zpl()
        let ci = try #require(zpl.range(of: "^CI28"))
        let firstField = try #require(zpl.range(of: "^FD"))
        #expect(ci.lowerBound < firstField.lowerBound)
    }

    @Test func nonASCIITextSurvivesVerbatim() throws {
        // ^CI28 puts the printer in UTF-8; the bytes must reach ^FD unmangled.
        let zpl = try ListLayout().makeLabel([.item("café piña jalapeño")], environment: environment).zpl()
        #expect(zpl.contains("^FDcafé piña jalapeño^FS"))
    }

    @Test func defaultFontIsDeclaredOnceRatherThanPerItem() throws {
        let zpl = try ListLayout()
            .makeLabel([.item("a"), .item("b"), .item("c")], environment: environment).zpl()
        #expect(zpl.contains("^CF0,50,50"))
        // The whole point: no per-item font command survives.
        #expect(!zpl.contains("^A0N,50,50"))
    }

    @Test func defaultFontDeclarationTracksTheItemFontSize() throws {
        var layout = ListLayout()
        layout.itemFontSize = 30
        let zpl = try layout.makeLabel([.item("small")], environment: environment).zpl()
        #expect(zpl.contains("^CF0,30,30"))
    }

    // MARK: - ^FH hex escaping

    @Test func commandIntroducersAreHexEscapedRatherThanStripped() throws {
        let zpl = try ListLayout()
            .makeLabel([.item("bad^XZand~JAmore")], environment: environment).zpl()
        #expect(zpl.contains("^FH^FDbad_5EXZand_7EJAmore^FS"))
        // Exactly one ^XZ: the label terminator, not one smuggled in via text.
        #expect(zpl.components(separatedBy: "^XZ").count - 1 == 1)
    }

    @Test func hexEscapeIntroducerIsItselfEscaped() throws {
        // With ^FH active, a literal '_' would otherwise start an escape and
        // silently eat the next two characters.
        let zpl = try ListLayout()
            .makeLabel([.item("snake_case_name")], environment: environment).zpl()
        #expect(zpl.contains("^FH^FDsnake_5Fcase_5Fname^FS"))
    }

    @Test func headerTextIsEscapedToo() throws {
        let zpl = try ListLayout()
            .makeLabel([.header("A^B~C_D:")], environment: environment).zpl()
        #expect(zpl.contains("^FH^FDA_5EB_7EC_5FD:^FS"))
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
        #expect(zpl.contains("^CF0,30,30"))
        #expect(zpl.contains("^FO40,60^FH^FDsmall^FS"))          // 20 + 30 + 10
    }

    @Test func printWidthIsDerivedFromTheEnvironmentByDefault() throws {
        let narrowEnvironment = ZPLEnvironment(stock: Stock.Preset.label2x1, device: Device.Preset.ZD620)
        let zpl = try ListLayout().makeLabel([.item("eggs")], environment: narrowEnvironment).zpl()
        #expect(zpl.contains("^PW600"))
    }

    @Test func explicitPrintWidthOverridesTheEnvironment() throws {
        var layout = ListLayout()
        layout.printWidthDots = 800
        let narrowEnvironment = ZPLEnvironment(stock: Stock.Preset.label2x1, device: Device.Preset.ZD620)
        let zpl = try layout.makeLabel([.item("eggs")], environment: narrowEnvironment).zpl()
        #expect(zpl.contains("^PW800"))
    }
}
