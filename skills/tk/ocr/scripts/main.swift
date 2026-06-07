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

let usage = """
usage: run-ocr.sh [options] [file-or-folder ...]

Options:
  -r, --recursive      Process supported files under folders recursively.
      --skip-existing  Do not overwrite existing non-empty .txt outputs.
      --overwrite      Overwrite existing .txt outputs (default).
      --report PATH    Write a TSV processing report.
  -h, --help           Show this help.
"""

enum ExitCode: Int32 {
    case success = 0
    case partialFailure = 1
    case invalidInvocation = 2
}

enum OCRToolError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case missingOptionValue(String)
    case targetDoesNotExist(String)
    case targetIsNotFileOrDirectory(String)
    case cannotListDirectory(String)
    case cannotOpenPDF(String)
    case cannotReadPDFPage(Int)
    case cannotCreateBitmapContext(Int)
    case cannotCreateBitmapImage(Int)
    case cannotOpenImage(String)
    case cannotCreateImage(String)
    case unsupportedFile(String)
    case pdftotextFailed(String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "\(message)\n\(usage)"
        case .missingOptionValue(let option):
            return "missing value for \(option)\n\(usage)"
        case .targetDoesNotExist(let path):
            return "target does not exist: \(path)"
        case .targetIsNotFileOrDirectory(let path):
            return "target is not a file or directory: \(path)"
        case .cannotListDirectory(let path):
            return "could not list directory: \(path)"
        case .cannotOpenPDF(let path):
            return "could not open PDF: \(path)"
        case .cannotReadPDFPage(let index):
            return "could not read PDF page: \(index + 1)"
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
        case .pdftotextFailed(let message):
            return "pdftotext fallback failed: \(message)"
        }
    }
}

struct Options {
    var recursive = false
    var skipExisting = false
    var reportURL: URL?
    var targets: [URL] = []
}

struct TargetFile {
    let inputURL: URL
    let outputURL: URL
}

struct Extraction {
    let text: String
    let method: String
    let pages: Int
}

struct ReportRow {
    let inputPath: String
    let outputPath: String
    let status: String
    let method: String
    let pages: String
    let error: String
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
    let base: String
    if nsError.domain != NSCocoaErrorDomain || nsError.code != 0 {
        base = "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
    } else {
        base = String(describing: error)
    }

    if isLikelyVisionSandboxError(nsError: nsError, message: base) {
        return "\(base) (Vision OCR may be blocked by the current sandbox; retry outside the sandbox.)"
    }

    return base
}

func isLikelyVisionSandboxError(nsError: NSError, message: String) -> Bool {
    if nsError.domain == "NSOSStatusErrorDomain", nsError.code == -6662 {
        return true
    }

    return message.contains("CVPixelBuffer") || message.contains("Foundation._GenericObjCError(0)")
}

func parseArguments(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "-h", "--help":
            print(usage)
            exit(ExitCode.success.rawValue)
        case "-r", "--recursive":
            options.recursive = true
        case "--skip-existing":
            options.skipExisting = true
        case "--overwrite":
            options.skipExisting = false
        case "--report":
            index += 1
            guard index < arguments.count else {
                throw OCRToolError.missingOptionValue(argument)
            }
            options.reportURL = resolveURL(arguments[index])
        default:
            if argument.hasPrefix("-") {
                throw OCRToolError.invalidArguments("unknown option: \(argument)")
            }
            options.targets.append(resolveURL(argument))
        }

        index += 1
    }

    if options.targets.isEmpty {
        options.targets = [resolveURL("\(FileManager.default.currentDirectoryPath)/tmp")]
    }

    return options
}

func resolveURL(_ rawPath: String) -> URL {
    let expandedPath = (rawPath as NSString).expandingTildeInPath
    if expandedPath.hasPrefix("/") {
        return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(expandedPath)
        .standardizedFileURL
}

func targetFiles(from targets: [URL], recursive: Bool) throws -> [TargetFile] {
    var files: [TargetFile] = []
    let fileManager = FileManager.default

    for target in targets {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            throw OCRToolError.targetDoesNotExist(target.path)
        }

        if isDirectory.boolValue {
            files.append(contentsOf: try targetFiles(in: target, recursive: recursive))
            continue
        }

        guard isSupportedFile(target) else {
            throw OCRToolError.unsupportedFile(target.path)
        }

        files.append(TargetFile(inputURL: target, outputURL: outputURL(for: target)))
    }

    return files.sorted {
        $0.inputURL.path.localizedStandardCompare($1.inputURL.path) == .orderedAscending
    }
}

func targetFiles(in directory: URL, recursive: Bool) throws -> [TargetFile] {
    let fileManager = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey]
    var files: [URL] = []

    if recursive {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { url, _ in
                writeStandardError("could not list directory entry: \(url.path)")
                return true
            }
        ) else {
            throw OCRToolError.cannotListDirectory(directory.path)
        }

        for case let url as URL in enumerator {
            if isSupportedRegularFile(url, keys: keys) {
                files.append(url.standardizedFileURL)
            }
        }
    } else {
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

        files = entries
            .filter { isSupportedRegularFile($0, keys: keys) }
            .map { $0.standardizedFileURL }
    }

    return files.map { TargetFile(inputURL: $0, outputURL: outputURL(for: $0)) }
}

func isSupportedRegularFile(_ url: URL, keys: [URLResourceKey]) -> Bool {
    let values = try? url.resourceValues(forKeys: Set(keys))
    guard values?.isRegularFile == true else {
        return false
    }

    return isSupportedFile(url)
}

func isSupportedFile(_ url: URL) -> Bool {
    supportedExtensions.contains(url.pathExtension.lowercased())
}

func outputURL(for inputURL: URL) -> URL {
    inputURL.deletingPathExtension().appendingPathExtension("txt")
}

func hasExistingOutput(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
        return false
    }

    return values.isRegularFile == true && (values.fileSize ?? 0) > 0
}

func extractText(from fileURL: URL) throws -> Extraction {
    switch fileURL.pathExtension.lowercased() {
    case "pdf":
        do {
            return try extractTextFromPDF(fileURL)
        } catch {
            if let fallback = try? extractTextWithPDFToText(fileURL), !fallback.text.isEmpty {
                return fallback
            }
            throw error
        }
    case "jpg", "jpeg", "png":
        return try extractTextFromImage(fileURL)
    default:
        throw OCRToolError.unsupportedFile(fileURL.path)
    }
}

func extractTextFromImage(_ fileURL: URL) throws -> Extraction {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
        throw OCRToolError.cannotOpenImage(fileURL.path)
    }

    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = imageOrientation(from: properties)

    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw OCRToolError.cannotCreateImage(fileURL.path)
    }

    let normalizedImage = try normalizedRGBImage(from: image)
    let text = try recognizeText(in: normalizedImage, orientation: orientation)
    return Extraction(text: text, method: "vision", pages: 1)
}

func extractTextFromPDF(_ fileURL: URL) throws -> Extraction {
    guard let document = PDFDocument(url: fileURL) else {
        throw OCRToolError.cannotOpenPDF(fileURL.path)
    }

    guard document.pageCount > 0 else {
        return Extraction(text: "", method: "empty-pdf", pages: 0)
    }

    var pageTexts: [String] = []
    pageTexts.reserveCapacity(document.pageCount)
    var usedVision = false
    var usedPDFKitText = false

    for index in 0..<document.pageCount {
        print("  page \(index + 1)/\(document.pageCount)")
        fflush(stdout)

        guard let page = document.page(at: index) else {
            throw OCRToolError.cannotReadPDFPage(index)
        }

        do {
            let image = try renderPDFPage(page, index: index)
            let recognizedText = try recognizeText(in: image, orientation: .up)
            usedVision = true
            pageTexts.append(recognizedText)
        } catch {
            if let fallbackText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fallbackText.isEmpty {
                usedPDFKitText = true
                pageTexts.append(fallbackText)
            } else {
                throw error
            }
        }
    }

    let method: String
    switch (usedVision, usedPDFKitText) {
    case (true, true):
        method = "vision+pdfkit-text"
    case (true, false):
        method = "vision"
    case (false, true):
        method = "pdfkit-text"
    case (false, false):
        method = "empty-pdf"
    }

    return Extraction(text: pageTexts.joined(separator: "\n\n"), method: method, pages: document.pageCount)
}

func extractTextWithPDFToText(_ fileURL: URL) throws -> Extraction {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pdftotext", "-enc", "UTF-8", "-layout", fileURL.path, "-"]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        throw OCRToolError.pdftotextFailed(error.localizedDescription)
    }

    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let outputText = String(data: outputData, encoding: .utf8) ?? ""
    let errorText = String(data: errorData, encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
        let message = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        throw OCRToolError.pdftotextFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message)
    }

    let pages = PDFDocument(url: fileURL)?.pageCount ?? 0
    return Extraction(text: outputText, method: "pdftotext", pages: pages)
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

func normalizedRGBImage(from image: CGImage) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw OCRToolError.cannotCreateImage("normalized bitmap")
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    guard let normalizedImage = context.makeImage() else {
        throw OCRToolError.cannotCreateImage("normalized image")
    }

    return normalizedImage
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

func writeReport(_ rows: [ReportRow], to reportURL: URL) throws {
    let parentURL = reportURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

    let header = "input\toutput\tstatus\tmethod\tpages\terror"
    let body = rows.map { row in
        [
            tsv(row.inputPath),
            tsv(row.outputPath),
            tsv(row.status),
            tsv(row.method),
            tsv(row.pages),
            tsv(row.error)
        ].joined(separator: "\t")
    }

    try ([header] + body).joined(separator: "\n").appending("\n")
        .write(to: reportURL, atomically: true, encoding: .utf8)
}

func tsv(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
}

func run() throws -> ExitCode {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let files = try targetFiles(from: options.targets, recursive: options.recursive)

    print("Scanning: \(options.targets.map { $0.path }.joined(separator: ", "))")
    print("Found: \(files.count) file(s)")

    var successCount = 0
    var failureCount = 0
    var skippedCount = 0
    var reportRows: [ReportRow] = []

    for file in files {
        if options.skipExisting && hasExistingOutput(file.outputURL) {
            skippedCount += 1
            print("[SKIP] \(file.inputURL.lastPathComponent) -> \(file.outputURL.lastPathComponent)")
            reportRows.append(ReportRow(
                inputPath: file.inputURL.path,
                outputPath: file.outputURL.path,
                status: "skip",
                method: "",
                pages: "",
                error: ""
            ))
            continue
        }

        do {
            let extraction = try extractText(from: file.inputURL)
            try writeText(extraction.text, to: file.outputURL)
            successCount += 1
            print("[OK] \(file.inputURL.lastPathComponent) -> \(file.outputURL.lastPathComponent) [\(extraction.method)]")
            reportRows.append(ReportRow(
                inputPath: file.inputURL.path,
                outputPath: file.outputURL.path,
                status: "ok",
                method: extraction.method,
                pages: "\(extraction.pages)",
                error: ""
            ))
        } catch {
            let message = errorMessage(error)
            failureCount += 1
            print("[FAIL] \(file.inputURL.lastPathComponent): \(message)")
            reportRows.append(ReportRow(
                inputPath: file.inputURL.path,
                outputPath: file.outputURL.path,
                status: "fail",
                method: "",
                pages: "",
                error: message
            ))
        }
    }

    if let reportURL = options.reportURL {
        try writeReport(reportRows, to: reportURL)
        print("Report: \(reportURL.path)")
    }

    print("Done. success=\(successCount) skipped=\(skippedCount) failed=\(failureCount)")

    return failureCount == 0 ? .success : .partialFailure
}

do {
    let code = try run()
    exit(code.rawValue)
} catch {
    failBeforeProcessing(error)
}
