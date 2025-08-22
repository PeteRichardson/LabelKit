//
//  Labelary.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation

enum LabelaryError: Error {
    case invalidDPmm
    case badURL
    case httpError(Int, String)
    case emptyData
}

public func fetchLabelImageData(
    dpmm: Int,  // e.g. 8 (203 dpi), 12 (300 dpi)
    widthMM: Double,  // label width in mm
    heightMM: Double,  // label height in mm
    zpl: String,  // your ZPL
    index: Int = 0,  // page index
    acceptMime: String = "image/png"  // "image/png" or "application/pdf"
) async throws -> Data {

    let allowed = [6, 8, 12, 24]  // Labelary-supported DPmm
    guard allowed.contains(dpmm) else { throw LabelaryError.invalidDPmm }

    // Convert to inches for Labelary API
    let widthInches = widthMM / 25.4
    let heightInches = heightMM / 25.4
    let fmt = { (v: Double) in String(format: "%.3f", v).replacingOccurrences(of: ",", with: ".") }
    let sizeComponent = "\(fmt(widthInches))x\(fmt(heightInches))"

    let urlString =
        "https://api.labelary.com/v1/printers/\(dpmm)dpmm/labels/\(sizeComponent)/\(index)/"
    guard let url = URL(string: urlString) else { throw LabelaryError.badURL }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(acceptMime, forHTTPHeaderField: "Accept")
    request.httpBody = zpl.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else { throw LabelaryError.emptyData }
    guard (200..<300).contains(http.statusCode) else {
        let snippet = String(data: data, encoding: .utf8) ?? ""
        throw LabelaryError.httpError(http.statusCode, snippet)
    }
    guard !data.isEmpty else { throw LabelaryError.emptyData }

    return data
}
