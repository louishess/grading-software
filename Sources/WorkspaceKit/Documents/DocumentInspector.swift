import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum DocumentInspector {
  private static let acceptedImageTypes: Set<String> = [
    UTType.jpeg.identifier,
    UTType.png.identifier,
    UTType.heic.identifier,
    UTType.heif.identifier,
  ]

  public static func inspect(
    url: URL,
    limits: DocumentImportLimits = .default
  ) throws -> DocumentInspection {
    try Task.checkCancellation()
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    } catch {
      throw DocumentFailure.accessDenied
    }

    guard values.isRegularFile == true else { throw DocumentFailure.accessDenied }
    let byteCount = Int64(values.fileSize ?? 0)
    guard byteCount > 0 else { throw DocumentFailure.damagedDocument }
    guard byteCount <= limits.maximumByteCount else {
      throw DocumentFailure.fileTooLarge(byteCount)
    }

    if isPDF(url: url) {
      return try inspectPDF(url: url, limits: limits)
    }
    return try inspectImage(url: url, limits: limits)
  }

  private static func isPDF(url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    return handle.readData(ofLength: 5) == Data("%PDF-".utf8)
  }

  private static func inspectPDF(
    url: URL,
    limits: DocumentImportLimits
  ) throws -> DocumentInspection {
    guard let document = PDFDocument(url: url) else { throw DocumentFailure.damagedDocument }
    guard !document.isEncrypted else { throw DocumentFailure.encryptedPDF }
    let pageCount = document.pageCount
    guard pageCount > 0 else { throw DocumentFailure.emptyDocument }
    guard pageCount <= limits.maximumPageCount else {
      throw DocumentFailure.tooManyPages(pageCount)
    }

    var pages: [DocumentPageRecord] = []
    pages.reserveCapacity(pageCount)
    for index in 0..<pageCount {
      try Task.checkCancellation()
      guard let page = document.page(at: index) else { throw DocumentFailure.damagedDocument }
      let media = page.bounds(for: .mediaBox)
      let crop = page.bounds(for: .cropBox)
      guard media.isFiniteAndPositive, crop.isFiniteAndPositive else {
        throw DocumentFailure.damagedDocument
      }
      pages.append(
        DocumentPageRecord(
          index: index,
          mediaBox: PageRectangle(media),
          cropBox: PageRectangle(crop),
          rotation: DocumentGeometry.normalizedRotation(page.rotation)
        ))
    }
    return DocumentInspection(typeIdentifier: UTType.pdf.identifier, pages: pages)
  }

  private static func inspectImage(
    url: URL,
    limits: DocumentImportLimits
  ) throws -> DocumentInspection {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let type = CGImageSourceGetType(source) as String?
    else {
      throw DocumentFailure.unsupportedType(url.pathExtension.lowercased())
    }
    guard acceptedImageTypes.contains(type) else { throw DocumentFailure.unsupportedType(type) }
    guard CGImageSourceGetCount(source) == 1 else { throw DocumentFailure.damagedDocument }
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let pixelWidth = integer(properties[kCGImagePropertyPixelWidth]),
      let pixelHeight = integer(properties[kCGImagePropertyPixelHeight]),
      pixelWidth > 0, pixelHeight > 0
    else {
      throw DocumentFailure.damagedDocument
    }
    guard pixelWidth <= limits.maximumImageDimension,
      pixelHeight <= limits.maximumImageDimension,
      Int64(pixelWidth) * Int64(pixelHeight) <= limits.maximumImagePixelCount
    else {
      throw DocumentFailure.imageTooLarge(width: pixelWidth, height: pixelHeight)
    }

    let orientation = integer(properties[kCGImagePropertyOrientation]) ?? 1
    let swapsAxes = [5, 6, 7, 8].contains(orientation)
    let dpiWidth = positiveDouble(properties[kCGImagePropertyDPIWidth]) ?? 72
    let dpiHeight = positiveDouble(properties[kCGImagePropertyDPIHeight]) ?? 72
    let rawWidth = Double(pixelWidth) * 72 / dpiWidth
    let rawHeight = Double(pixelHeight) * 72 / dpiHeight
    let width = swapsAxes ? rawHeight : rawWidth
    let height = swapsAxes ? rawWidth : rawHeight
    let bounds = PageRectangle(x: 0, y: 0, width: width, height: height)
    return DocumentInspection(
      typeIdentifier: type,
      pages: [DocumentPageRecord(index: 0, mediaBox: bounds, cropBox: bounds)]
    )
  }

  private static func integer(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    return nil
  }

  private static func positiveDouble(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, number.doubleValue > 0 else { return nil }
    return number.doubleValue
  }
}

extension PageRectangle {
  init(_ rect: CGRect) {
    self.init(
      x: Double(rect.origin.x),
      y: Double(rect.origin.y),
      width: Double(rect.size.width),
      height: Double(rect.size.height)
    )
  }

  var cgRect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }
}

extension CGRect {
  fileprivate var isFiniteAndPositive: Bool {
    origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
      && size.width > 0 && size.height > 0
  }
}
