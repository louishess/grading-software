import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import WorkspaceKit

private struct DocumentCheckFailure: Error, CustomStringConvertible {
  var description: String
}

public func runDocumentChecks() async throws {
  try geometryRoundTripsAcrossRotationsAndCropOrigins()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "grading-document-checks-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let sourceURL = directory.appendingPathComponent("synthetic.pdf")
  try makeSyntheticPDF(at: sourceURL)
  let sourceData = try Data(contentsOf: sourceURL)
  let input = try makeInput(url: sourceURL)
  try check(input.record.pages.count == 2, "PDF inspection must retain both pages")
  try check(
    input.record.pages[0].cropBox.x == 20,
    "The nonzero crop-box origin returned by PDFKit must be preserved"
  )
  try check(input.record.pages[1].rotation == 90, "Page rotation must be preserved")

  let firstPage = input.record.pages[0]
  let cropRegion = PageRegion(
    documentID: input.record.id,
    documentRevisionID: input.record.revisionID,
    pageID: firstPage.id,
    bounds: PageRectangle(x: 40, y: 50, width: 160, height: 60)
  )
  let renderedPage = try DocumentRenderer.renderPage(input: input, pageID: firstPage.id, scale: 1)
  try check(renderedPage.image.width > 0, "PDF page rendering must produce pixels")
  let croppedImage = try DocumentRenderer.image(for: cropRegion, input: input, scale: 2)
  try check(
    croppedImage.width > 0 && croppedImage.height > 0, "Region rendering must produce pixels")

  let highlight = DocumentMarks.highlight(region: cropRegion)
  let noteRegion = PageRegion(
    documentID: input.record.id,
    documentRevisionID: input.record.revisionID,
    pageID: firstPage.id,
    bounds: PageRectangle(x: 210, y: 500, width: 180, height: 72)
  )
  let note = DocumentMarks.note(region: noteRegion, text: "Check this reasoning.")
  let ink = try DocumentMarks.ink(
    input: input,
    pageID: firstPage.id,
    points: [
      PagePoint(x: 40, y: 400), PagePoint(x: 80, y: 430), PagePoint(x: 130, y: 405),
    ]
  )
  let displayMask = DocumentMark(region: cropRegion, kind: .displayMask)

  let editableURL = directory.appendingPathComponent("editable.pdf")
  try DocumentPDFExporter.export(
    inputs: [input], marks: [highlight, note, ink, displayMask], flattened: false,
    to: editableURL
  )
  guard let editable = PDFDocument(url: editableURL), let editablePage = editable.page(at: 0) else {
    throw DocumentCheckFailure(description: "Editable PDF must reopen")
  }
  try check(editable.pageCount == 2, "Editable export must preserve page order")
  try check(
    editablePage.annotations.count == 4, "Editable export must preserve and add annotations")
  try check(
    editablePage.annotations.contains(where: { $0.contents == "Check this reasoning." }),
    "Editable note text must round-trip"
  )

  let flattenedURL = directory.appendingPathComponent("flattened.pdf")
  try DocumentPDFExporter.export(
    inputs: [input], marks: [highlight, note, ink, displayMask], flattened: true,
    to: flattenedURL
  )
  guard let flattened = PDFDocument(url: flattenedURL), let flattenedPage = flattened.page(at: 0)
  else { throw DocumentCheckFailure(description: "Flattened PDF must reopen") }
  try check(flattenedPage.annotations.isEmpty, "Flattened export must burn in annotations")
  try check(try Data(contentsOf: sourceURL) == sourceData, "Export must not change original bytes")

  let hardLinkURL = directory.appendingPathComponent("original-hardlink.pdf")
  try FileManager.default.linkItem(at: sourceURL, to: hardLinkURL)
  do {
    try DocumentPDFExporter.export(
      inputs: [input], marks: [], flattened: false, to: hardLinkURL
    )
    throw DocumentCheckFailure(description: "Export must reject a hard link to the original")
  } catch let error as DocumentFailure {
    guard case .exportFailed = error else { throw error }
  }

  let damagedURL = directory.appendingPathComponent("damaged.pdf")
  try Data("%PDF-not-a-document".utf8).write(to: damagedURL)
  do {
    _ = try DocumentInspector.inspect(url: damagedURL)
    throw DocumentCheckFailure(description: "Damaged PDF must be rejected")
  } catch let error as DocumentFailure {
    try check(error == .damagedDocument, "Damaged PDF must report a document failure")
  }

  let imageURL = directory.appendingPathComponent("oriented.jpg")
  try makeSyntheticImage(at: imageURL, orientation: 6)
  let imageInput = try makeInput(url: imageURL)
  try check(imageInput.record.pages.count == 1, "Image import must create one page")
  try check(
    imageInput.record.pages[0].cropBox.height > imageInput.record.pages[0].cropBox.width,
    "EXIF orientation must swap the canonical page dimensions"
  )
  let imagePDFURL = directory.appendingPathComponent("image-export.pdf")
  try DocumentPDFExporter.export(
    inputs: [imageInput], marks: [], flattened: false, to: imagePDFURL
  )
  try check(PDFDocument(url: imagePDFURL)?.pageCount == 1, "Image input must export as a PDF page")

  let ocr = try await DocumentOCR.recognize(input: input, languages: ["en-US"])
  try check(!ocr.blocks.isEmpty, "Vision should recognize the synthetic high-contrast text")
  try check(
    ocr.blocks.allSatisfy { $0.region.documentRevisionID == input.record.revisionID },
    "Every OCR block must retain its source revision"
  )
  let corrected = correctedRecord(from: ocr)
  let rerun = try await DocumentOCR.recognize(input: input, languages: ["en-US"])
  let merged = DocumentOCR.mergingCorrections(from: corrected, into: rerun)
  try check(
    merged.blocks.contains(where: { $0.correction == "Teacher correction" }),
    "A rerun must preserve an overlapping teacher correction"
  )

  let cancelled = Task { try await DocumentOCR.recognize(input: input, languages: ["en-US"]) }
  cancelled.cancel()
  do {
    _ = try await cancelled.value
    throw DocumentCheckFailure(description: "Cancelled OCR must not report success")
  } catch is CancellationError {
    // Expected.
  }
}

private func geometryRoundTripsAcrossRotationsAndCropOrigins() throws {
  for rotation in [0, 90, 180, 270] {
    let page = DocumentPageRecord(
      index: 0,
      mediaBox: PageRectangle(x: -40, y: -30, width: 700, height: 900),
      cropBox: PageRectangle(x: -20, y: 10, width: 620, height: 760),
      rotation: rotation
    )
    let original = CGPoint(x: 123.25, y: 456.5)
    let display = DocumentGeometry.pageToDisplay(original, page: page)
    let restored = DocumentGeometry.displayToPage(display, page: page)
    try check(abs(original.x - restored.x) < 0.000_001, "X coordinate must round-trip")
    try check(abs(original.y - restored.y) < 0.000_001, "Y coordinate must round-trip")
    let originalRect = PageRectangle(x: 15, y: 45, width: 123, height: 87)
    let displayRect = DocumentGeometry.displayRect(for: originalRect, page: page)
    let restoredRect = DocumentGeometry.pageRect(for: displayRect, page: page)
    try check(abs(originalRect.x - restoredRect.x) < 0.000_001, "Rect X must round-trip")
    try check(abs(originalRect.y - restoredRect.y) < 0.000_001, "Rect Y must round-trip")
    try check(
      abs(originalRect.width - restoredRect.width) < 0.000_001, "Rect width must round-trip")
    try check(
      abs(originalRect.height - restoredRect.height) < 0.000_001, "Rect height must round-trip")
  }
}

private func makeSyntheticPDF(at url: URL) throws {
  let document = PDFDocument()
  for index in 0..<2 {
    let image = NSImage(size: CGSize(width: 640, height: 800))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 640, height: 800)).fill()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 42, weight: .bold),
      .foregroundColor: NSColor.black,
    ]
    "SYNTHETIC OCR 42 PAGE \(index + 1)".draw(
      at: CGPoint(x: 80, y: 600),
      withAttributes: attributes
    )
    image.unlockFocus()
    guard let page = PDFPage(image: image) else {
      throw DocumentCheckFailure(description: "Synthetic PDF page creation failed")
    }
    page.setBounds(
      CGRect(x: -40, y: -30, width: 700, height: 900),
      for: .mediaBox
    )
    page.setBounds(
      CGRect(x: -20, y: 10, width: 620, height: 760),
      for: .cropBox
    )
    page.rotation = index == 0 ? 0 : 90
    if index == 0 {
      let existing = PDFAnnotation(
        bounds: CGRect(x: 450, y: 80, width: 50, height: 50),
        forType: .circle,
        withProperties: nil
      )
      page.addAnnotation(existing)
    }
    document.insert(page, at: index)
  }
  guard document.write(to: url) else {
    throw DocumentCheckFailure(description: "Synthetic PDF write failed")
  }
}

private func makeSyntheticImage(at url: URL, orientation: Int) throws {
  guard
    let context = CGContext(
      data: nil,
      width: 120,
      height: 80,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else { throw DocumentCheckFailure(description: "Synthetic image context creation failed") }
  context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
  context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 8, y: 8, width: 52, height: 28))
  guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    )
  else { throw DocumentCheckFailure(description: "Synthetic image creation failed") }
  CGImageDestinationAddImage(
    destination,
    image,
    [kCGImagePropertyOrientation: orientation] as CFDictionary
  )
  guard CGImageDestinationFinalize(destination) else {
    throw DocumentCheckFailure(description: "Synthetic image write failed")
  }
}

private func makeInput(url: URL) throws -> DocumentInput {
  let inspection = try DocumentInspector.inspect(url: url)
  let data = try Data(contentsOf: url)
  let asset = AssetReference(
    sha256: "synthetic-document-hash",
    byteCount: Int64(data.count),
    typeIdentifier: inspection.typeIdentifier,
    relativePath: url.lastPathComponent
  )
  let record = SourceDocumentRecord(
    originalName: url.lastPathComponent,
    asset: asset,
    pages: inspection.pages
  )
  return DocumentInput(record: record, url: url)
}

private func correctedRecord(from record: OCRRecord) -> OCRRecord {
  var corrected = record
  if !corrected.blocks.isEmpty { corrected.blocks[0].correction = "Teacher correction" }
  return corrected
}

private func check(
  _ condition: @autoclosure () throws -> Bool,
  _ message: String
) throws {
  guard try condition() else { throw DocumentCheckFailure(description: message) }
}
