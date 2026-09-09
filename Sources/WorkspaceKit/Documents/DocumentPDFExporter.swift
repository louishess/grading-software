import CoreGraphics
import Foundation
import PDFKit

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

public enum DocumentPDFExporter {
  public static func export(
    inputs: [DocumentInput],
    marks: [DocumentMark],
    flattened: Bool,
    to destination: URL
  ) throws {
    try Task.checkCancellation()
    guard !inputs.isEmpty else { throw DocumentFailure.emptyDocument }
    try ensureDestinationDoesNotReplaceOriginal(destination, inputs: inputs)

    let output = PDFDocument()
    var pageLookup: [PageKey: PDFPage] = [:]
    var outputIndex = 0
    for input in inputs {
      try Task.checkCancellation()
      let pages = try exportPages(for: input)
      for (record, page) in pages {
        output.insert(page, at: outputIndex)
        pageLookup[PageKey(documentID: input.record.id, pageID: record.id)] = page
        outputIndex += 1
      }
    }

    for mark in marks where mark.kind != .displayMask {
      try Task.checkCancellation()
      guard
        let input = inputs.first(where: {
          $0.record.id == mark.region.documentID
            && $0.record.revisionID == mark.region.documentRevisionID
        })
      else { throw DocumentFailure.mismatchedDocument }
      try DocumentMarks.validate(mark, input: input)
      guard
        let page = pageLookup[
          PageKey(documentID: mark.region.documentID, pageID: mark.region.pageID)
        ]
      else { throw DocumentFailure.missingPage(mark.region.pageID) }
      page.addAnnotation(try annotation(for: mark))
    }

    let directory = destination.deletingLastPathComponent()
    let temporary = directory.appendingPathComponent(".\(UUID().uuidString).pdf")
    let options: [PDFDocumentWriteOption: Any] =
      flattened ? [.burnInAnnotationsOption: true] : [:]
    guard output.write(to: temporary, withOptions: options) else {
      throw DocumentFailure.exportFailed("PDFKit did not write the output file.")
    }
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try FileManager.default.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw DocumentFailure.exportFailed(error.localizedDescription)
    }
  }

  private static func exportPages(
    for input: DocumentInput
  ) throws -> [(DocumentPageRecord, PDFPage)] {
    if input.record.asset.typeIdentifier == "com.adobe.pdf" {
      guard let source = PDFDocument(url: input.url) else { throw DocumentFailure.damagedDocument }
      guard !source.isEncrypted else { throw DocumentFailure.encryptedPDF }
      return try input.record.pages.map { record in
        guard let sourcePage = source.page(at: record.index),
          let copy = sourcePage.copy() as? PDFPage
        else { throw DocumentFailure.missingPage(record.id) }
        return (record, copy)
      }
    }

    guard input.record.pages.count == 1, let record = input.record.pages.first else {
      throw DocumentFailure.damagedDocument
    }
    let rendered = try DocumentRenderer.renderPage(input: input, pageID: record.id, scale: 2)
    #if canImport(AppKit)
      let platformImage = NSImage(
        cgImage: rendered.image,
        size: DocumentGeometry.displaySize(for: record)
      )
      guard let page = PDFPage(image: platformImage) else { throw DocumentFailure.renderingFailed }
    #elseif canImport(UIKit)
      let platformImage = UIImage(cgImage: rendered.image)
      guard let page = PDFPage(image: platformImage) else { throw DocumentFailure.renderingFailed }
    #else
      throw DocumentFailure.renderingFailed
    #endif
    page.setBounds(record.mediaBox.cgRect, for: .mediaBox)
    page.setBounds(record.cropBox.cgRect, for: .cropBox)
    page.rotation = DocumentGeometry.normalizedRotation(record.rotation)
    return [(record, page)]
  }

  static func annotation(for mark: DocumentMark) throws -> PDFAnnotation {
    let bounds = mark.region.bounds.cgRect
    let annotation: PDFAnnotation
    switch mark.kind {
    case .highlight:
      annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
      let points = [
        CGPoint(x: 0, y: bounds.height),
        CGPoint(x: bounds.width, y: bounds.height),
        CGPoint(x: 0, y: 0),
        CGPoint(x: bounds.width, y: 0),
      ]
      #if canImport(AppKit)
        annotation.quadrilateralPoints = points.map(NSValue.init(point:))
      #elseif canImport(UIKit)
        annotation.quadrilateralPoints = points.map(NSValue.init(cgPoint:))
      #endif
    case .note:
      guard !mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DocumentFailure.invalidMark("A text note cannot be empty.")
      }
      annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
      annotation.contents = mark.text
      annotation.font = .systemFont(ofSize: 11)
      annotation.fontColor = platformTextColor
      annotation.interiorColor = platformNoteColor
    case .ink:
      guard mark.points.count >= 2, mark.lineWidth.isFinite, mark.lineWidth > 0 else {
        throw DocumentFailure.invalidMark("An ink mark needs a visible stroke.")
      }
      annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
      #if canImport(AppKit)
        let path = NSBezierPath()
        path.move(
          to: CGPoint(
            x: mark.points[0].x - mark.region.bounds.x,
            y: mark.points[0].y - mark.region.bounds.y
          ))
        for point in mark.points.dropFirst() {
          path.line(
            to: CGPoint(
              x: point.x - mark.region.bounds.x,
              y: point.y - mark.region.bounds.y
            ))
        }
        path.lineWidth = mark.lineWidth
        annotation.add(path)
      #elseif canImport(UIKit)
        let path = UIBezierPath()
        path.move(
          to: CGPoint(
            x: mark.points[0].x - mark.region.bounds.x,
            y: mark.points[0].y - mark.region.bounds.y
          ))
        for point in mark.points.dropFirst() {
          path.addLine(
            to: CGPoint(
              x: point.x - mark.region.bounds.x,
              y: point.y - mark.region.bounds.y
            ))
        }
        path.lineWidth = mark.lineWidth
        annotation.add(path)
      #else
        throw DocumentFailure.invalidMark("Ink export is unavailable on this platform.")
      #endif
    case .displayMask:
      throw DocumentFailure.invalidMark("Display masks are never exported as annotations.")
    }
    annotation.color = platformColor(hex: mark.colorHex)
    annotation.shouldDisplay = true
    annotation.shouldPrint = true
    return annotation
  }

  private static func ensureDestinationDoesNotReplaceOriginal(
    _ destination: URL,
    inputs: [DocumentInput]
  ) throws {
    let outputPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
    let originalPaths = Set(
      inputs.map { $0.url.standardizedFileURL.resolvingSymlinksInPath().path }
    )
    guard !originalPaths.contains(outputPath) else {
      throw DocumentFailure.exportFailed("Choose a destination other than an original file.")
    }
    guard FileManager.default.fileExists(atPath: destination.path) else { return }
    let destinationValues = try? destination.resourceValues(forKeys: [.fileResourceIdentifierKey])
    let destinationIdentifier = destinationValues?.fileResourceIdentifier as? NSObject
    guard
      !inputs.contains(where: {
        let originalValues = try? $0.url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        guard
          let originalIdentifier = originalValues?.fileResourceIdentifier as? NSObject,
          let destinationIdentifier
        else { return false }
        return originalIdentifier.isEqual(destinationIdentifier)
      })
    else {
      throw DocumentFailure.exportFailed("Choose a destination other than an original file.")
    }
  }

  #if canImport(AppKit)
    private static func platformColor(hex: String) -> NSColor {
      NSColor(cgColor: cgColor(hex: hex)) ?? .systemYellow
    }
    private static var platformTextColor: NSColor { .black }
    private static var platformNoteColor: NSColor { .white.withAlphaComponent(0.92) }
  #elseif canImport(UIKit)
    private static func platformColor(hex: String) -> UIColor {
      UIColor(cgColor: cgColor(hex: hex))
    }
    private static var platformTextColor: UIColor { .black }
    private static var platformNoteColor: UIColor { .white.withAlphaComponent(0.92) }
  #endif

  private static func cgColor(hex: String) -> CGColor {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
      return CGColor(red: 0.9, green: 0.68, blue: 0.19, alpha: 0.75)
    }
    return CGColor(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 0.75
    )
  }

  private struct PageKey: Hashable {
    var documentID: UUID
    var pageID: UUID
  }
}
