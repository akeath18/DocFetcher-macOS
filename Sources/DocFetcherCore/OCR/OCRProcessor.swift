import Foundation
#if canImport(Vision) && canImport(PDFKit) && canImport(CoreGraphics)
import Vision
import PDFKit
import CoreGraphics
import ImageIO
#endif

public protocol OCRProcessor: Sendable {
    func recognize(url: URL) async throws -> OCRResult
}

/// Tries each processor in order, returning the first successful result.
public struct FallbackOCRProcessor: OCRProcessor {
    private let processors: [OCRProcessor]
    public init(_ processors: [OCRProcessor]) { self.processors = processors }

    public func recognize(url: URL) async throws -> OCRResult {
        var lastError: Error = ParserError.unsupported("no OCR engine available")
        for p in processors {
            do { return try await p.recognize(url: url) } catch { lastError = error }
        }
        throw lastError
    }

    /// Vision on macOS, with Tesseract as a fallback for image files.
    public static func platformDefault() -> OCRProcessor {
        var list: [OCRProcessor] = []
        #if canImport(Vision) && canImport(PDFKit) && canImport(CoreGraphics)
        list.append(VisionOCRProcessor())
        #endif
        list.append(TesseractOCRProcessor())
        return FallbackOCRProcessor(list)
    }
}

/// Runs the `tesseract` command-line tool (if installed) on image files and reads per-word confidences.
public struct TesseractOCRProcessor: OCRProcessor {
    public init() {}

    public func recognize(url: URL) async throws -> OCRResult {
        guard ["png", "jpg", "jpeg", "tif", "tiff"].contains(url.pathExtension.lowercased()) else {
            throw ParserError.unsupported("Tesseract fallback handles image files only")
        }
        let data = try FileUtils.runTool(["tesseract", url.path, "stdout", "tsv"])
        var lines: [Int: [String]] = [:]
        var confs: [Double] = []
        for row in String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst() {
            let cols = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 12, let conf = Double(cols[10]), conf >= 0 else { continue }
            let word = String(cols[11]).trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            let key = (Int(cols[2]) ?? 0) * 10_000 + (Int(cols[3]) ?? 0) * 100 + (Int(cols[4]) ?? 0)
            lines[key, default: []].append(word)
            confs.append(conf / 100)
        }
        let text = lines.keys.sorted().map { lines[$0]!.joined(separator: " ") }.joined(separator: "\n")
        let mean = confs.isEmpty ? nil : confs.reduce(0, +) / Double(confs.count)
        return OCRTextCleaner.makeResult(rawText: text, engineConfidence: mean)
    }
}

#if canImport(Vision) && canImport(PDFKit) && canImport(CoreGraphics)
/// Apple Vision text recognition for scanned PDFs and images.
public struct VisionOCRProcessor: OCRProcessor {
    public var renderScale: CGFloat = 2.5
    public init() {}

    public func recognize(url: URL) async throws -> OCRResult {
        var pageTexts: [String] = []
        var pageConfs: [Double] = []
        for image in try images(for: url) {
            let (text, conf) = try recognize(image)
            pageTexts.append(text)
            pageConfs.append(conf)
        }
        let mean = pageConfs.isEmpty ? nil : pageConfs.reduce(0, +) / Double(pageConfs.count)
        return OCRTextCleaner.makeResult(rawText: pageTexts.joined(separator: "\n\n"), engineConfidence: mean,
                                         pageConfidences: pageConfs)
    }

    private func images(for url: URL) throws -> [CGImage] {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw ParserError.corrupted("cannot open PDF") }
            var out: [CGImage] = []
            for i in 0..<min(doc.pageCount, 200) {
                guard let page = doc.page(at: i) else { continue }
                let box = page.bounds(for: .mediaBox)
                let w = Int(box.width * renderScale), h = Int(box.height * renderScale)
                guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                       space: CGColorSpaceCreateDeviceRGB(),
                                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.scaleBy(x: renderScale, y: renderScale)
                page.draw(with: .mediaBox, to: ctx)
                if let img = ctx.makeImage() { out.append(img) }
            }
            return out
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ParserError.corrupted("cannot read image")
        }
        return [img]
    }

    private func recognize(_ image: CGImage) throws -> (String, Double) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
        let conf = candidates.isEmpty ? 0 : candidates.map { Double($0.confidence) }.reduce(0, +) / Double(candidates.count)
        return (text, conf)
    }
}
#endif
