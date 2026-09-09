import CoreGraphics
import Foundation

public enum DocumentGeometry {
  public static func normalizedRotation(_ rotation: Int) -> Int {
    let value = rotation % 360
    return value < 0 ? value + 360 : value
  }

  public static func displaySize(for page: DocumentPageRecord) -> CGSize {
    let crop = page.cropBox.cgRect
    switch normalizedRotation(page.rotation) {
    case 90, 270:
      return CGSize(width: crop.height, height: crop.width)
    default:
      return crop.size
    }
  }

  /// Converts canonical unrotated PDF page coordinates to rotated display coordinates.
  /// Both coordinate systems use a lower-left origin.
  public static func pageToDisplay(
    _ point: CGPoint,
    page: DocumentPageRecord
  ) -> CGPoint {
    let crop = page.cropBox.cgRect
    let x = point.x - crop.minX
    let y = point.y - crop.minY
    switch normalizedRotation(page.rotation) {
    case 90:
      return CGPoint(x: y, y: crop.width - x)
    case 180:
      return CGPoint(x: crop.width - x, y: crop.height - y)
    case 270:
      return CGPoint(x: crop.height - y, y: x)
    default:
      return CGPoint(x: x, y: y)
    }
  }

  /// Converts rotated display coordinates to canonical unrotated PDF page coordinates.
  /// Both coordinate systems use a lower-left origin.
  public static func displayToPage(
    _ point: CGPoint,
    page: DocumentPageRecord
  ) -> CGPoint {
    let crop = page.cropBox.cgRect
    let local: CGPoint
    switch normalizedRotation(page.rotation) {
    case 90:
      local = CGPoint(x: crop.width - point.y, y: point.x)
    case 180:
      local = CGPoint(x: crop.width - point.x, y: crop.height - point.y)
    case 270:
      local = CGPoint(x: point.y, y: crop.height - point.x)
    default:
      local = point
    }
    return CGPoint(x: local.x + crop.minX, y: local.y + crop.minY)
  }

  public static func displayRect(
    for pageRect: PageRectangle,
    page: DocumentPageRecord
  ) -> CGRect {
    boundingRect(
      corners(of: pageRect.cgRect).map { pageToDisplay($0, page: page) }
    )
  }

  public static func pageRect(
    for displayRect: CGRect,
    page: DocumentPageRecord
  ) -> PageRectangle {
    PageRectangle(
      boundingRect(
        corners(of: displayRect).map { displayToPage($0, page: page) }
      ))
  }

  /// Vision observations use normalized lower-left image coordinates.
  public static func pageRegion(
    fromVisionNormalizedBounds bounds: CGRect,
    input: DocumentInput,
    page: DocumentPageRecord
  ) throws -> PageRegion {
    guard bounds.isFiniteAndNonnegative else { throw DocumentFailure.invalidRegion }
    let size = displaySize(for: page)
    let displayRect = CGRect(
      x: bounds.minX * size.width,
      y: bounds.minY * size.height,
      width: bounds.width * size.width,
      height: bounds.height * size.height
    )
    let region = PageRegion(
      documentID: input.record.id,
      documentRevisionID: input.record.revisionID,
      pageID: page.id,
      bounds: pageRect(for: displayRect, page: page)
    )
    try validate(region, input: input)
    return region
  }

  public static func visionNormalizedBounds(
    for region: PageRegion,
    input: DocumentInput
  ) throws -> CGRect {
    let page = try page(for: region, input: input)
    try validate(region, input: input)
    let display = displayRect(for: region.bounds, page: page)
    let size = displaySize(for: page)
    return CGRect(
      x: display.minX / size.width,
      y: display.minY / size.height,
      width: display.width / size.width,
      height: display.height / size.height
    )
  }

  public static func validate(_ region: PageRegion, input: DocumentInput) throws {
    guard region.coordinateVersion == 1,
      region.documentID == input.record.id,
      region.documentRevisionID == input.record.revisionID
    else {
      throw DocumentFailure.mismatchedDocument
    }
    let page = try page(for: region, input: input)
    let bounds = region.bounds.cgRect
    let crop = page.cropBox.cgRect
    let media = page.mediaBox.cgRect
    guard bounds.isFiniteAndPositive,
      crop.isFiniteAndPositive,
      media.isFiniteAndPositive,
      [0, 90, 180, 270].contains(normalizedRotation(page.rotation)),
      media.contains(crop),
      bounds.minX >= crop.minX - 0.001,
      bounds.minY >= crop.minY - 0.001,
      bounds.maxX <= crop.maxX + 0.001,
      bounds.maxY <= crop.maxY + 0.001
    else {
      throw DocumentFailure.invalidRegion
    }
  }

  public static func page(
    for region: PageRegion,
    input: DocumentInput
  ) throws -> DocumentPageRecord {
    guard let page = input.record.pages.first(where: { $0.id == region.pageID }) else {
      throw DocumentFailure.missingPage(region.pageID)
    }
    return page
  }

  public static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
    guard contentSize.width > 0, contentSize.height > 0,
      bounds.width > 0, bounds.height > 0
    else { return .zero }
    let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
    let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    return CGRect(
      x: bounds.midX - size.width / 2,
      y: bounds.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  private static func corners(of rect: CGRect) -> [CGPoint] {
    [
      CGPoint(x: rect.minX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.minX, y: rect.maxY),
      CGPoint(x: rect.maxX, y: rect.maxY),
    ]
  }

  private static func boundingRect(_ points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .zero }
    var minimumX = first.x
    var maximumX = first.x
    var minimumY = first.y
    var maximumY = first.y
    for point in points.dropFirst() {
      minimumX = min(minimumX, point.x)
      maximumX = max(maximumX, point.x)
      minimumY = min(minimumY, point.y)
      maximumY = max(maximumY, point.y)
    }
    return CGRect(
      x: minimumX,
      y: minimumY,
      width: maximumX - minimumX,
      height: maximumY - minimumY
    )
  }
}

extension CGRect {
  fileprivate var isFiniteAndPositive: Bool {
    minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
      && width > 0 && height > 0
  }

  fileprivate var isFiniteAndNonnegative: Bool {
    minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
      && minX >= 0 && minY >= 0 && width > 0 && height > 0
      && maxX <= 1.000_001 && maxY <= 1.000_001
  }
}
