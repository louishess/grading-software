import CoreGraphics
import Foundation

public struct DocumentInspection: Hashable, Sendable {
  public var typeIdentifier: String
  public var pages: [DocumentPageRecord]

  public init(typeIdentifier: String, pages: [DocumentPageRecord]) {
    self.typeIdentifier = typeIdentifier
    self.pages = pages
  }
}

public struct DocumentInput: Hashable, Sendable {
  public var record: SourceDocumentRecord
  public var url: URL

  public init(record: SourceDocumentRecord, url: URL) {
    self.record = record
    self.url = url
  }
}

public struct DocumentImportLimits: Hashable, Sendable {
  public var maximumByteCount: Int64
  public var maximumPageCount: Int
  public var maximumImageDimension: Int
  public var maximumImagePixelCount: Int64

  public init(
    maximumByteCount: Int64 = 512 * 1_024 * 1_024,
    maximumPageCount: Int = 2_000,
    maximumImageDimension: Int = 30_000,
    maximumImagePixelCount: Int64 = 150_000_000
  ) {
    self.maximumByteCount = maximumByteCount
    self.maximumPageCount = maximumPageCount
    self.maximumImageDimension = maximumImageDimension
    self.maximumImagePixelCount = maximumImagePixelCount
  }

  public static let `default` = DocumentImportLimits()
}

public struct DocumentRenderLimits: Hashable, Sendable {
  public var maximumPixelCount: Int64
  public var maximumScale: Double

  public init(maximumPixelCount: Int64 = 40_000_000, maximumScale: Double = 4) {
    self.maximumPixelCount = maximumPixelCount
    self.maximumScale = maximumScale
  }

  public static let `default` = DocumentRenderLimits()
}

public struct RenderedDocumentPage: @unchecked Sendable {
  public var image: CGImage
  public var page: DocumentPageRecord
  public var scale: Double

  public init(image: CGImage, page: DocumentPageRecord, scale: Double) {
    self.image = image
    self.page = page
    self.scale = scale
  }
}

public enum DocumentFailure: Error, LocalizedError, Sendable, Equatable {
  case accessDenied
  case unsupportedType(String)
  case fileTooLarge(Int64)
  case damagedDocument
  case encryptedPDF
  case emptyDocument
  case tooManyPages(Int)
  case imageTooLarge(width: Int, height: Int)
  case missingPage(UUID)
  case mismatchedDocument
  case invalidRegion
  case invalidMark(String)
  case renderTooLarge(width: Int, height: Int)
  case renderingFailed
  case recognitionFailed(String)
  case exportFailed(String)
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "The selected file could not be read."
    case .unsupportedType(let type):
      return "The selected file type is unsupported: \(type)."
    case .fileTooLarge(let bytes):
      return "The selected file is too large (\(bytes) bytes)."
    case .damagedDocument:
      return "The selected document is damaged or unreadable."
    case .encryptedPDF:
      return "Encrypted PDF files are not supported in this version."
    case .emptyDocument:
      return "The selected document has no readable pages."
    case .tooManyPages(let count):
      return "The selected document has too many pages (\(count))."
    case .imageTooLarge(let width, let height):
      return "The selected image is too large (\(width) by \(height) pixels)."
    case .missingPage:
      return "The referenced page is no longer available."
    case .mismatchedDocument:
      return "The document revision does not match this operation."
    case .invalidRegion:
      return "The selected page region is invalid or outside the page."
    case .invalidMark(let message):
      return message
    case .renderTooLarge(let width, let height):
      return
        "Rendering this page at the requested size would be too large (\(width) by \(height) pixels)."
    case .renderingFailed:
      return "The document page could not be rendered."
    case .recognitionFailed(let message):
      return "Text recognition failed: \(message)"
    case .exportFailed(let message):
      return "The annotated PDF could not be exported: \(message)"
    case .cancelled:
      return "The operation was cancelled."
    }
  }
}
