import CoreGraphics
import Foundation

public enum DocumentMarks {
  public static func highlight(
    region: PageRegion,
    colorHex: String = "#E5AD31"
  ) -> DocumentMark {
    var mark = DocumentMark(region: region, kind: .highlight)
    mark.colorHex = colorHex
    return mark
  }

  public static func note(
    region: PageRegion,
    text: String,
    colorHex: String = "#FFF0A6"
  ) -> DocumentMark {
    var mark = DocumentMark(region: region, kind: .note, text: text)
    mark.colorHex = colorHex
    return mark
  }

  public static func ink(
    input: DocumentInput,
    pageID: UUID,
    points: [PagePoint],
    colorHex: String = "#D14A3A",
    lineWidth: Double = 2,
    pencilDrawing: Data? = nil,
    pencilContentVersion: Int? = nil,
    pencilCanvasTransform: [Double]? = nil
  ) throws -> DocumentMark {
    guard points.count >= 2, lineWidth.isFinite, lineWidth > 0 else {
      throw DocumentFailure.invalidMark("An ink mark needs a visible stroke.")
    }
    guard let page = input.record.pages.first(where: { $0.id == pageID }) else {
      throw DocumentFailure.missingPage(pageID)
    }
    let pagePoints = points.map { CGPoint(x: $0.x, y: $0.y) }
    let minimumX = pagePoints.map(\.x).min()!
    let maximumX = pagePoints.map(\.x).max()!
    let minimumY = pagePoints.map(\.y).min()!
    let maximumY = pagePoints.map(\.y).max()!
    let padding = CGFloat(lineWidth / 2)
    let proposed = CGRect(
      x: minimumX - padding,
      y: minimumY - padding,
      width: max(CGFloat(lineWidth), maximumX - minimumX + padding * 2),
      height: max(CGFloat(lineWidth), maximumY - minimumY + padding * 2)
    )
    let clipped = proposed.intersection(page.cropBox.cgRect)
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
      throw DocumentFailure.invalidRegion
    }
    let region = PageRegion(
      documentID: input.record.id,
      documentRevisionID: input.record.revisionID,
      pageID: pageID,
      bounds: PageRectangle(clipped)
    )
    var mark = DocumentMark(region: region, kind: .ink, points: points)
    mark.colorHex = colorHex
    mark.lineWidth = lineWidth
    mark.pencilDrawing = pencilDrawing
    mark.pencilContentVersion = pencilContentVersion
    mark.pencilCanvasTransform = pencilCanvasTransform
    try validate(mark, input: input)
    return mark
  }

  public static func validate(_ mark: DocumentMark, input: DocumentInput) throws {
    try DocumentGeometry.validate(mark.region, input: input)
    switch mark.kind {
    case .highlight, .displayMask:
      break
    case .note:
      guard !mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DocumentFailure.invalidMark("A text note cannot be empty.")
      }
    case .ink:
      guard mark.points.count >= 2, mark.lineWidth.isFinite, mark.lineWidth > 0 else {
        throw DocumentFailure.invalidMark("An ink mark needs a visible stroke.")
      }
      if mark.pencilDrawing != nil || mark.pencilContentVersion != nil
        || mark.pencilCanvasTransform != nil
      {
        guard let version = mark.pencilContentVersion, version >= 0,
          let transform = mark.pencilCanvasTransform,
          transform.count == 6,
          transform.allSatisfy(\.isFinite)
        else {
          throw DocumentFailure.invalidMark(
            "Pencil drawing data needs a content version and six-value canvas transform."
          )
        }
      }
      let crop = try DocumentGeometry.page(for: mark.region, input: input).cropBox.cgRect
      guard
        mark.points.allSatisfy({ point in
          point.x.isFinite && point.y.isFinite
            && crop.contains(CGPoint(x: point.x, y: point.y))
        })
      else {
        throw DocumentFailure.invalidMark("An ink stroke extends outside its source page.")
      }
    }
  }
}
