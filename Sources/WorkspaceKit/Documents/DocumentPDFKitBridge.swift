import Foundation
import PDFKit

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

@MainActor
public enum DocumentPDFKitBridge {
  public static func document(for input: DocumentInput) throws -> PDFDocument {
    if input.record.asset.typeIdentifier == "com.adobe.pdf" {
      guard let document = PDFDocument(url: input.url) else {
        throw DocumentFailure.damagedDocument
      }
      guard !document.isEncrypted else { throw DocumentFailure.encryptedPDF }
      guard document.pageCount == input.record.pages.count else {
        throw DocumentFailure.mismatchedDocument
      }
      return document
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
    let document = PDFDocument()
    document.insert(page, at: 0)
    return document
  }

  public static func region(
    from viewRect: CGRect,
    on pdfPage: PDFPage,
    input: DocumentInput,
    in pdfView: PDFView
  ) throws -> PageRegion {
    guard let document = pdfPage.document else { throw DocumentFailure.damagedDocument }
    let index = document.index(for: pdfPage)
    guard let page = input.record.pages.first(where: { $0.index == index }) else {
      throw DocumentFailure.missingPage(UUID())
    }
    let pageBounds = pdfView.convert(viewRect, to: pdfPage)
    let region = PageRegion(
      documentID: input.record.id,
      documentRevisionID: input.record.revisionID,
      pageID: page.id,
      bounds: PageRectangle(pageBounds.standardized)
    )
    try DocumentGeometry.validate(region, input: input)
    return region
  }

  public static func viewRect(
    for region: PageRegion,
    input: DocumentInput,
    in pdfView: PDFView
  ) throws -> CGRect {
    try DocumentGeometry.validate(region, input: input)
    guard let pageRecord = input.record.pages.first(where: { $0.id == region.pageID }),
      let document = pdfView.document,
      let pdfPage = document.page(at: pageRecord.index)
    else { throw DocumentFailure.missingPage(region.pageID) }
    return pdfView.convert(region.bounds.cgRect, from: pdfPage)
  }
}
