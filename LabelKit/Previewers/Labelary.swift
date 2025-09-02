//
//  ImagePrinter.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation


// MARK: - Labelary (network)

public struct LabelaryImageRenderer: ImageRenderer {
    
    

    let session: URLSession = .shared
    public func render(from zpl: String, options: ImageRenderOptions) async throws -> Data {
        
        let dpmm = Int(round(Double(options.geometry.dpi) / 25.4))  // e.g. 8 (203 dpi), 12 (300 dpi)
        let dpi = options.geometry.dpi
        let wInches = max(1, (options.geometry.widthDots ?? dpi) ) // fallback 1"
        let hInches = max(1, (options.geometry.heightDots ?? dpi) )
        let widthInches = Double(wInches) / Double(dpi)
        let heightInches = Double(hInches) / Double(dpi)
    
        let allowed = [6, 8, 12, 24]  // Labelary-supported DPmm
        guard allowed.contains(dpmm) else { throw LabelaryError.invalidDPmm }
        
        let fmt = { (v: Double) in String(format: "%.3f", v).replacingOccurrences(of: ",", with: ".") }
        let sizeComponent = "\(fmt(widthInches))x\(fmt(heightInches))"
        
        let urlString =
        "https://api.labelary.com/v1/printers/\(dpmm)dpmm/labels/\(sizeComponent)/0/"
        guard let url = URL(string: urlString) else { throw LabelaryError.badURL }
        
        print("urlstring: \(urlString)")
        
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
        // Basic Labelary API: /v1/printers/{DPI}/labels/{w}x{h}/0/
//        let dpi = options.geometry.dpi
//        let wInches = max(1, (options.geometry.widthDots ?? dpi) ) // fallback 1"
//        let hInches = max(1, (options.geometry.heightDots ?? dpi) )
//        let widthIn = Double(wInches) / Double(dpi)
//        let heightIn = Double(hInches) / Double(dpi)
//
//        guard let url = URL(string: "https://api.labelary.com/v1/printers/\(dpi)/labels/\(widthIn)x\(heightIn)/0/") else {
//            throw URLError(.badURL)
//        }
//        let urlString =
//            "https://api.labelary.com/v1/printers/\(dpmm)dpmm/labels/\(sizeComponent)/\(index)/"
//        guard let url = URL(string: urlString) else { throw LabelaryError.badURL }
//
//        print(url)
//        var req = URLRequest(url: url)
//        req.httpMethod = "POST"
//        req.httpBody = Data(zpl.utf8)
//        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
//
//        let (data, resp) = try await session.data(for: req)
//        print(resp)
//
//        guard (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
//            throw URLError(.badServerResponse)
//        }
//        return data
    }
    public init() {}
}

enum LabelaryError: Error {
    case invalidDPmm
    case badURL
    case httpError(Int, String)
    case emptyData
}

public func fetchLabelImageData(
    label: ZPLLabel,
    stock: Stock,
    dpi: DPI,
    index: Int = 0,  // page index
    acceptMime: String = "image/png"  // "image/png" or "application/pdf"
) async throws -> Data {
    let dpmm = Int(round(Double(dpi.rawValue) / 25.4))  // e.g. 8 (203 dpi), 12 (300 dpi)
    let widthInches = stock.widthInches
    let heightInches = stock.heightInches

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
    request.httpBody = try label.zpl().data(using: .utf8)

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
