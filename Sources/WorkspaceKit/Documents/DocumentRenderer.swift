import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

public enum DocumentRenderer {
  public static func renderPage(
    input: DocumentInput,
    pageID: UUID,
    scale: Double = 2,
    limits: DocumentRenderLimits = .default
  ) throws -> RenderedDocumentPage {
    try Task.checkCancellation()
    guard let pageRecord = input.record.pages.first(where: { $0.id == pageID }) else {
      throw DocumentFailure.missingPage(pageID)
    }
    let pixelSize = try validatedPixelSize(page: pageRecord, scale: scale, limits: limits)
    let image: CGImage
    if input.record.asset.typeIdentifier == UTType.pdf.identifier {
      image = try renderPDFPage(input: input, page: pageRecord, pixelSize: pixelSize)
    } else {
      image = try renderImage(input: input, pixelSize: pixelSize)
    }
    return RenderedDocumentPage(image: image, page: pageRecord, scale: scale)
  }

  public static func image(
    for region: PageRegion,
    input: DocumentInput,
    scale: Double = 2,
    limits: DocumentRenderLimits = .default
  ) throws -> CGImage {
    try DocumentGeometry.validate(region, input: input)
    let rendered = try renderPage(
      input: input,
      pageID: region.pageID,
      scale: scale,
      limits: limits
    )
    let displayBounds = DocumentGeometry.displayRect(for: region.bounds, page: rendered.page)
    let displaySize = DocumentGeometry.displaySize(for: rendered.page)
    let pixelsPerPointX = CGFloat(rendered.image.width) / displaySize.width
    let pixelsPerPointY = CGFloat(rendered.image.height) / displaySize.height
    let pixelRect = CGRect(
      x: displayBounds.minX * pixelsPerPointX,
      y: (displaySize.height - displayBounds.maxY) * pixelsPerPointY,
      width: displayBounds.width * pixelsPerPointX,
      height: displayBounds.height * pixelsPerPointY
    ).integral.intersection(
      CGRect(x: 0, y: 0, width: rendered.image.width, height: rendered.image.height)
    )
    guard pixelRect.width > 0, pixelRect.height > 0,
      let cropped = rendered.image.cropping(to: pixelRect)
    else {
      throw DocumentFailure.renderingFailed
    }
    return cropped
  }

  private static func validatedPixelSize(
    page: DocumentPageRecord,
    scale: Double,
    limits: DocumentRenderLimits
  ) throws -> CGSize {
    guard scale.isFinite, scale > 0, scale <= limits.maximumScale else {
      throw DocumentFailure.renderingFailed
    }
    let displaySize = DocumentGeometry.displaySize(for: page)
    let width = max(1, Int(ceil(displaySize.width * scale)))
    let height = max(1, Int(ceil(displaySize.height * scale)))
    guard Int64(width) * Int64(height) <= limits.maximumPixelCount else {
      throw DocumentFailure.renderTooLarge(width: width, height: height)
    }
    return CGSize(width: width, height: height)
  }

  private static func renderPDFPage(
    input: DocumentInput,
    page: DocumentPageRecord,
    pixelSize: CGSize
  ) throws -> CGImage {
    guard let document = PDFDocument(url: input.url) else { throw DocumentFailure.damagedDocument }
    guard !document.isEncrypted else { throw DocumentFailure.encryptedPDF }
    guard let pdfPage = document.page(at: page.index) else { throw DocumentFailure.damagedDocument }
    let thumbnail = pdfPage.thumbnail(of: pixelSize, for: .cropBox)
    #if canImport(AppKit)
      var proposedRect = CGRect(origin: .zero, size: thumbnail.size)
      guard
        let image = thumbnail.cgImage(
          forProposedRect: &proposedRect,
          context: nil,
          hints: nil
        )
      else { throw DocumentFailure.renderingFailed }
      return image
    #elseif canImport(UIKit)
      guard let image = thumbnail.cgImage else { throw DocumentFailure.renderingFailed }
      return image
    #else
      throw DocumentFailure.renderingFailed
    #endif
  }

  private static func renderImage(input: DocumentInput, pixelSize: CGSize) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(input.url as CFURL, nil) else {
      throw DocumentFailure.damagedDocument
    }
    let maximumDimension = max(Int(pixelSize.width), Int(pixelSize.height))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      throw DocumentFailure.damagedDocument
    }
    guard
      let context = CGContext(
        data: nil,
        width: Int(pixelSize.width),
        height: Int(pixelSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { throw DocumentFailure.renderingFailed }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: pixelSize))
    context.interpolationQuality = .high
    context.draw(oriented, in: CGRect(origin: .zero, size: pixelSize))
    guard let result = context.makeImage() else { throw DocumentFailure.renderingFailed }
    return result
  }
}
