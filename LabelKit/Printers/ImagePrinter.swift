//
//  ImagePrinter.swift
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
    label: ZPLLabel,
    zpl: String,  // your ZPL
    index: Int = 0,  // page index
    acceptMime: String = "image/png"  // "image/png" or "application/pdf"
) async throws -> Data {
    let dpmm = Int(round(Double(label.resolution) / 25.4))  // e.g. 8 (203 dpi), 12 (300 dpi)
    let widthInches = Double(label.width) / Double(label.resolution)            // label width in Inches
    let heightInches = Double(label.height) / Double(label.resolution)           // label height in Inches

    let allowed = [6, 8, 12, 24]  // Labelary-supported DPmm
    guard allowed.contains(dpmm) else { throw LabelaryError.invalidDPmm }

    let fmt = { (v: Double) in String(format: "%.3f", v).replacingOccurrences(of: ",", with: ".") }
    let sizeComponent = "\(fmt(widthInches))x\(fmt(heightInches))"

    let urlString =
        "https://api.labelary.com/v1/printers/\(dpmm)dpmm/labels/\(sizeComponent)/\(index)/"
    guard let url = URL(string: urlString) else { throw LabelaryError.badURL }
    
    print("urlstring: \(urlString)")

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



public func showImageInITerm2(data: Data) {
    // Base64-encode the image
    let base64 = data.base64EncodedString()

    // iTerm2 escape sequence format for inline images
    let esc = "\u{1b}"  // Escape character
    let osc = "]"
    let st = "\\"

    let header = "\(esc)\(osc)1337;File=inline=1;width=auto;height=auto;preserveAspectRatio=1:"
    let footer = "\(esc)\(st)"

    // Print the sequence to the terminal
    print("\(header)\(base64)\(footer)")
}
