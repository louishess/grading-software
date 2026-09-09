import Foundation
import PDFKit

@MainActor
public enum DocumentAnnotationProjector {
  /// Builds a disposable PDFKit presentation document. Sidecar marks remain authoritative.
  public static func presentationDocument(
    input: DocumentInput,
    marks: [DocumentMark]
  ) throws -> PDFDocument {
    let document = try DocumentPDFKitBridge.document(for: input)
    for mark in marks where mark.kind != .displayMask {
      guard mark.region.documentID == input.record.id else { continue }
      try DocumentMarks.validate(mark, input: input)
      guard let record = input.record.pages.first(where: { $0.id == mark.region.pageID }),
        let page = document.page(at: record.index)
      else { throw DocumentFailure.missingPage(mark.region.pageID) }
      page.addAnnotation(try DocumentPDFExporter.annotation(for: mark))
    }
    return document
  }
}
