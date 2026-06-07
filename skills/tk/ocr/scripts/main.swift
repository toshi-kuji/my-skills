import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision
import Darwin

let supportedExtensions: Set<String> = ["pdf", "jpg", "jpeg", "png"]
let preferredRecognitionLanguages = ["ja-JP", "en-US"]
let pdfRenderScale: CGFloat = 2.5
let maxRenderedPDFDimension: CGFloat = 5000

enum ExitCode: Int32 {
    case success = 0
    case partialFailure = 1
    case invalidInvocation = 2
}

enum OCRToolError: Error, CustomStringConvertible {
    case invalidArguments
    case targetIsNotDirectory(String)
    case cannotListDirectory(String)
    case cannotOpenPDF(String)
    case cannotReadPDFPage(Int)
    case cannotRenderPDFPage(Int)
    case cannotCreateBitmapContext(Int)
    case cannotCreateBitmapImage(Int)
    case cannotOpenImage(String)
    case cannotCreateImage(String)
    case unsupportedFile(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: run-ocr.sh [folder]"
        case .targetIsNotDirectory(let path):
            return "target is not a directory: \(path)"
        case .cannotListDirectory(let path):
            return "could not list directory: \(path)"
        case .cannotOpenPDF(let path):
            return "could not open PDF: \(path)"
        case .cannotReadPDFPage(let index):
            return "could not read PDF page: \(index + 1)"
        case .cannotRenderPDFPage(let index):
            return "could not render PDF page: \(index + 1)"
        case .cannotCreateBitmapContext(let index):
            return "could not create bitmap context for PDF page: \(index + 1)"
        case .cannotCreateBitmapImage(let index):
            return "could not create bitmap image for PDF page: \(index + 1)"
        case .cannotOpenImage(let path):
            return "could not open image: \(path)"
        case .cannotCreateImage(let path):
            return "could not create image: \(path)"
        case .unsupportedFile(let path):
            return "unsupported file type: \(path)"
        }
    }
}

func failBeforeProcessing(_ error: Error) -> Never {
    writeStandardError(errorMessage(error))
    exit(ExitCode.invalidInvocation.rawValue)
}

func writeStandardError(_ message: String) {
    if let data = "\(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func errorMessage(_ error: Error) -> String {
    if let toolError = error as? OCRToolError {
        return toolError.description
    }

    let nsError = error as NSError
    if nsError.domain != NSCocoaErrorDomain || nsError.code != 0 {
        return "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    }

    return String(describing: error)
}

func resolveTargetDirectory(from arguments: [String]) throws -> URL {
    guard arguments.count <= 1 else {
        throw OCRToolError.invalidArguments
    }

    let rawPath = arguments.first ?? "/"
    let expandedPath = (rawPath as NSString).expandingTildeInPath
    let fileManager = FileManager.default

    let url: URL
    if expandedPath == "." {
        url = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    } else if expandedPath.hasPrefix("/") {
        url = URL(fileURLWithPath: expandedPath, isDirectory: true)
    } else {
        url = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expandedPath, isDirectory: true)
    }

    let standardizedURL = url.standardizedFileURL
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw OCRToolError.targetIsNotDirectory(standardizedURL.path)
    }

    return standardizedURL
}

func targetFiles(in directory: URL) throws -> [URL] {
    let fileManager = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey]

    let entries: [URL]
    do {
        entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        )
    } catch {
        throw OCRToolError.cannotListDirectory(directory.path)
    }

    return entries
        .filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else {
                return false
            }

            return supportedExtensions.contains(url.pathExtension.lowercased())
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

func outputURL(for inputURL: URL) -> URL {
    inputURL.deletingPathExtension().appendingPathExtension("txt")
}

func extractText(from fileURL: URL) throws -> String {
    switch fileURL.pathExtension.lowercased() {
    case "pdf":
        return try extractTextFromPDF(fileURL)
    case "jpg", "jpeg", "png":
        return try extractTextFromImage(fileURL)
    default:
        throw OCRToolError.unsupportedFile(fileURL.path)
    }
}

func extractTextFromImage(_ fileURL: URL) throws -> String {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
        throw OCRToolError.cannotOpenImage(fileURL.path)
    }

    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = imageOrientation(from: properties)

    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw OCRToolError.cannotCreateImage(fileURL.path)
    }

    return try recognizeText(in: image, orientation: orientation)
}

func extractTextFromPDF(_ fileURL: URL) throws -> String {
    guard let document = PDFDocument(url: fileURL) else {
        throw OCRToolError.cannotOpenPDF(fileURL.path)
    }

    guard document.pageCount > 0 else {
        return ""
    }

    var pageTexts: [String] = []
    pageTexts.reserveCapacity(document.pageCount)

    for index in 0..<document.pageCount {
        print("  page \(index + 1)/\(document.pageCount)")
        fflush(stdout)

        guard let page = document.page(at: index) else {
            throw OCRToolError.cannotReadPDFPage(index)
        }

        do {
            let image = try renderPDFPage(page, index: index)
            let recognizedText = try recognizeText(in: image, orientation: .up)
            pageTexts.append(recognizedText)
        } catch {
            if let fallbackText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fallbackText.isEmpty {
                pageTexts.append(fallbackText)
            } else {
                throw error
            }
        }
    }

    return pageTexts.joined(separator: "\n\n")
}

func renderPDFPage(_ page: PDFPage, index: Int) throws -> CGImage {
    let bounds = page.bounds(for: .cropBox)
    let largestSide = max(bounds.width, bounds.height)
    let scale = min(pdfRenderScale, maxRenderedPDFDimension / max(largestSide, 1))
    let pixelWidth = max(Int((bounds.width * scale).rounded(.up)), 1)
    let pixelHeight = max(Int((bounds.height * scale).rounded(.up)), 1)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw OCRToolError.cannotCreateBitmapContext(index)
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    page.draw(with: .cropBox, to: context)
    context.restoreGState()

    guard let image = context.makeImage() else {
        throw OCRToolError.cannotCreateBitmapImage(index)
    }

    return image
}

func imageOrientation(from properties: [CFString: Any]?) -> CGImagePropertyOrientation {
    guard let number = properties?[kCGImagePropertyOrientation] as? NSNumber,
          let orientation = CGImagePropertyOrientation(rawValue: number.uint32Value) else {
        return .up
    }

    return orientation
}

func recognizeText(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
    let availablePreferredLanguages = preferredRecognitionLanguages.filter { supportedLanguages.contains($0) }
    if !availablePreferredLanguages.isEmpty {
        request.recognitionLanguages = availablePreferredLanguages
    }

    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
    try handler.perform([request])

    let observations = request.results ?? []
    return observations
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
}

func writeText(_ text: String, to url: URL) throws {
    let output = text.hasSuffix("\n") ? text : "\(text)\n"
    try output.write(to: url, atomically: true, encoding: .utf8)
}

func run() throws -> ExitCode {
    let targetDirectory = try resolveTargetDirectory(from: Array(CommandLine.arguments.dropFirst()))
    let files = try targetFiles(in: targetDirectory)

    print("Scanning: \(targetDirectory.path)")
    print("Found: \(files.count) file(s)")

    var successCount = 0
    var failureCount = 0

    for fileURL in files {
        let outputFileURL = outputURL(for: fileURL)

        do {
            let text = try extractText(from: fileURL)
            try writeText(text, to: outputFileURL)
            successCount += 1
            print("[OK] \(fileURL.lastPathComponent) -> \(outputFileURL.lastPathComponent)")
        } catch {
            failureCount += 1
            print("[FAIL] \(fileURL.lastPathComponent): \(errorMessage(error))")
        }
    }

    print("Done. success=\(successCount) failed=\(failureCount)")

    return failureCount == 0 ? .success : .partialFailure
}

do {
    let code = try run()
    exit(code.rawValue)
} catch {
    failBeforeProcessing(error)
}
