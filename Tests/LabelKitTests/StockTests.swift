//
//  StockTests.swift
//  LabelKitTests
//

import Testing
@testable import LabelKit

@Suite("Stock geometry math")
struct StockTests {

    @Test func widthDotsRoundsToNearestDot() {
        // 1.5in @ 300dpi = 450 dots exactly.
        let stock = Stock(widthInches: 1.5, heightInches: 1.0, isContinuous: false, gapInches: 0)
        #expect(stock.widthDots(at: .dpi300) == 450)

        // 1.505in @ 203dpi = 305.515 -> rounds to 306.
        let rounding = Stock(widthInches: 1.505, heightInches: 1.0, isContinuous: false, gapInches: 0)
        #expect(rounding.widthDots(at: .dpi203) == 306)
    }

    @Test func heightDotsIsNilForContinuousStock() {
        #expect(Stock.Preset.label4x.heightDots(at: .dpi300) == nil)
    }

    @Test func heightDotsRoundsToNearestDotForFixedStock() {
        // 1in @ 300dpi = 300 dots exactly.
        #expect(Stock.Preset.label2x1.heightDots(at: .dpi300) == 300)
        // 1in @ 203dpi = 203 dots exactly.
        #expect(Stock.Preset.label2x1.heightDots(at: .dpi203) == 203)
    }

    @Test func gapDotsRoundsToNearestDot() {
        // 0.125in @ 300dpi = 37.5 -> rounds to 38 (round-half-away-from-zero).
        #expect(Stock.Preset.label2x1.gapDots(at: .dpi300) == 38)
    }

    @Test func widthMMConvertsInchesDirectly() {
        // 2in * 25.4mm/in = 50.8mm.
        #expect(Stock.Preset.label2x1.widthMM() == 50.8)
    }

    @Test func heightMMIsNilForContinuousStock() {
        #expect(Stock.Preset.label4x.heightMM() == nil)
    }

    @Test func heightMMConvertsInchesDirectlyForFixedStock() {
        // 1in * 25.4mm/in = 25.4mm.
        #expect(Stock.Preset.label2x1.heightMM() == 25.4)
    }

    @Test func gapMMConvertsInchesDirectly() {
        // 0.125in * 25.4mm/in = 3.175mm.
        #expect(Stock.Preset.label2x1.gapMM() == 3.175)
    }

    @Test func label2x1PresetMatchesDocumentedDimensions() {
        let stock = Stock.Preset.label2x1
        #expect(stock.widthInches == 2.0)
        #expect(stock.heightInches == 1.0)
        #expect(stock.isContinuous == false)
        #expect(stock.gapInches == 0.125)
    }

    @Test func label4xPresetMatchesDocumentedDimensions() {
        let stock = Stock.Preset.label4x
        #expect(stock.widthInches == 4.0)
        #expect(stock.heightInches == nil)
        #expect(stock.isContinuous == true)
        #expect(stock.gapInches == 0.0)
    }

    @Test func equalStocksAreEqualAndHash() {
        let a = Stock(widthInches: 2, heightInches: 1, isContinuous: false, gapInches: 0.125)
        let b = Stock(widthInches: 2, heightInches: 1, isContinuous: false, gapInches: 0.125)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
