//
//  ImagePrinter.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation

public struct LabelaryRenderer: ImageRenderer {

    let session: URLSession = .shared
    public func render(from zpl: String, options: ImageRenderOptions) async throws -> Data {
        
        // Conversion routed through RenderGeometry's shared helpers (docs/reviews/
        // PROJECT_REVIEW.md F6, GitHub #7), which zpl2png.swift now uses too.
        let dpmm = options.geometry.dotsPerMillimeter  // e.g. 8 (203 dpi), 12 (300 dpi)
        let dpi = options.geometry.dpi
        let wDots = max(1, (options.geometry.widthDots ?? dpi) ) // fallback 1"
        let hDots = max(1, (options.geometry.heightDots ?? dpi) )
        let widthInches = options.geometry.inches(fromDots: wDots)
        let heightInches = options.geometry.inches(fromDots: hDots)
    
        let allowed = [6, 8, 12, 24]  // Labelary-supported DPmm
        guard allowed.contains(dpmm) else { throw LabelaryError.invalidDPmm }
        
        let fmt = { (v: Double) in String(format: "%.3f", v).replacingOccurrences(of: ",", with: ".") }
        let sizeComponent = "\(fmt(widthInches))x\(fmt(heightInches))"
        
        let urlString =
        "https://api.labelary.com/v1/printers/\(dpmm)dpmm/labels/\(sizeComponent)/0/"
        guard let url = URL(string: urlString) else { throw LabelaryError.badURL }
        
        //print("urlstring: \(urlString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/PNG", forHTTPHeaderField: "Accept")
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
    public init() {}
}

enum LabelaryError: Error {
    case invalidDPmm
    case badURL
    case httpError(Int, String)
    case emptyData
}

extension LabelaryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidDPmm:
            return "Labelary only supports 6, 8, 12, or 24 dots/mm"
        case .badURL:
            return "Could not construct a valid Labelary request URL"
        case let .httpError(status, body):
            return "Labelary request failed with HTTP \(status): \(body)"
        case .emptyData:
            return "Labelary returned an empty response"
        }
    }
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
