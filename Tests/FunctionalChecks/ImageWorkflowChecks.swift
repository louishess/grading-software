import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WorkspaceKit

private struct ImageWorkflowCheckFailure: Error, CustomStringConvertible {
  var description: String
}

private struct TestColor {
  var red: Double
  var green: Double
  var blue: Double

  static let red = TestColor(red: 0.92, green: 0.10, blue: 0.10)
  static let green = TestColor(red: 0.10, green: 0.86, blue: 0.18)
  static let blue = TestColor(red: 0.10, green: 0.24, blue: 0.90)
  static let yellow = TestColor(red: 0.92, green: 0.86, blue: 0.10)
}

public func runImageWorkflowChecks() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "grading-image-workflow-\(UUID().uuidString.lowercased())", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let sourceImage = try makeQuadrantImage(width: 120, height: 80)
  let pngURL = directory.appendingPathComponent("quadrants.png")
  try writeImage(sourceImage, to: pngURL, type: .png, orientation: 1)
  let pngOriginal = try Data(contentsOf: pngURL)
  let pngInput = try inspectInput(at: pngURL)
  try imageCheck(
    pngInput.record.asset.typeIdentifier == UTType.png.identifier,
    "PNG inspection returned the wrong type identifier.")
  try assertPageSize(pngInput, width: 120, height: 80, label: "PNG")
  let pngPage = pngInput.record.pages[0]
  let renderedPNG = try DocumentRenderer.renderPage(
    input: pngInput, pageID: pngPage.id, scale: 1)
  try imageCheck(
    renderedPNG.image.width == 120 && renderedPNG.image.height == 80,
    "PNG rendering changed the expected pixel dimensions.")
  try assertQuadrants(
    renderedPNG.image,
    expected: [.red, .green, .blue, .yellow],
    tolerance: 0.12,
    label: "PNG")

  let topLeftRegion = PageRegion(
    documentID: pngInput.record.id,
    documentRevisionID: pngInput.record.revisionID,
    pageID: pngPage.id,
    bounds: PageRectangle(x: 0, y: 40, width: 60, height: 40))
  let topLeftCrop = try DocumentRenderer.image(
    for: topLeftRegion, input: pngInput, scale: 1)
  try imageCheck(
    topLeftCrop.width == 60 && topLeftCrop.height == 40,
    "The top-left source crop has the wrong geometry.")
  try assertColor(
    sampleCenter(topLeftCrop), near: .red, tolerance: 0.12,
    message: "A top-left page region did not align with the red source quadrant.")

  let bottomRightRegion = PageRegion(
    documentID: pngInput.record.id,
    documentRevisionID: pngInput.record.revisionID,
    pageID: pngPage.id,
    bounds: PageRectangle(x: 60, y: 0, width: 60, height: 40))
  let bottomRightCrop = try DocumentRenderer.image(
    for: bottomRightRegion, input: pngInput, scale: 1)
  try assertColor(
    sampleCenter(bottomRightCrop), near: .yellow, tolerance: 0.12,
    message: "A bottom-right page region did not align with the yellow source quadrant.")
  try imageCheck(
    try Data(contentsOf: pngURL) == pngOriginal,
    "PNG inspection or rendering modified the original bytes.")

  let jpegURL = directory.appendingPathComponent("oriented-6.jpg")
  try writeImage(sourceImage, to: jpegURL, type: .jpeg, orientation: 6)
  let jpegOriginal = try Data(contentsOf: jpegURL)
  let jpegInput = try inspectInput(at: jpegURL)
  try imageCheck(
    jpegInput.record.asset.typeIdentifier == UTType.jpeg.identifier,
    "JPEG inspection returned the wrong type identifier.")
  try assertPageSize(jpegInput, width: 80, height: 120, label: "orientation-6 JPEG")
  let jpegPage = jpegInput.record.pages[0]
  let renderedJPEG = try DocumentRenderer.renderPage(
    input: jpegInput, pageID: jpegPage.id, scale: 1)
  try imageCheck(
    renderedJPEG.image.width == 80 && renderedJPEG.image.height == 120,
    "EXIF orientation 6 did not rotate the rendered JPEG dimensions.")
  try assertQuadrants(
    renderedJPEG.image,
    expected: [.blue, .red, .yellow, .green],
    tolerance: 0.24,
    label: "orientation-6 JPEG")
  try imageCheck(
    try Data(contentsOf: jpegURL) == jpegOriginal,
    "JPEG inspection or rendering modified the original bytes.")

  try testTruncatedImageRejection(original: pngOriginal, pathExtension: "png", in: directory)
  try testTruncatedImageRejection(original: jpegOriginal, pathExtension: "jpg", in: directory)
  try await testCancellation(input: pngInput, url: pngURL)
  try testHEICWhenAvailable(sourceImage: sourceImage, directory: directory)
}

private func testTruncatedImageRejection(
  original: Data, pathExtension: String, in directory: URL
) throws {
  let url = directory.appendingPathComponent("truncated.\(pathExtension)")
  let retainedByteCount = max(16, original.count / 3)
  try original.prefix(retainedByteCount).write(to: url)
  do {
    let input = try inspectInput(at: url)
    let page = try imageRequire(input.record.pages.first, "A truncated image had no page record.")
    _ = try DocumentRenderer.renderPage(input: input, pageID: page.id, scale: 1)
    throw ImageWorkflowCheckFailure(
      description: "A truncated \(pathExtension.uppercased()) became a usable rendered document.")
  } catch let failure as ImageWorkflowCheckFailure {
    throw failure
  } catch let failure as DocumentFailure {
    switch failure {
    case .damagedDocument, .unsupportedType:
      return
    default:
      throw ImageWorkflowCheckFailure(
        description:
          "A truncated \(pathExtension.uppercased()) returned an unrelated failure: \(failure).")
    }
  }
}

private func testCancellation(input: DocumentInput, url: URL) async throws {
  let inspection = Task { () throws -> DocumentInspection in
    withUnsafeCurrentTask { $0?.cancel() }
    return try DocumentInspector.inspect(url: url)
  }
  do {
    _ = try await inspection.value
    throw ImageWorkflowCheckFailure(description: "Cancelled image inspection reported success.")
  } catch is CancellationError {
    // Expected.
  }

  let pageID = try imageRequire(input.record.pages.first, "The PNG page is missing.").id
  let rendering = Task { () throws -> RenderedDocumentPage in
    withUnsafeCurrentTask { $0?.cancel() }
    return try DocumentRenderer.renderPage(input: input, pageID: pageID, scale: 1)
  }
  do {
    _ = try await rendering.value
    throw ImageWorkflowCheckFailure(description: "Cancelled image rendering reported success.")
  } catch is CancellationError {
    // Expected.
  }
}

private func testHEICWhenAvailable(sourceImage: CGImage, directory: URL) throws {
  let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
  guard destinationTypes.contains(UTType.heic.identifier) else {
    print("SKIP image workflow HEIC: this runtime has no HEIC encoder")
    return
  }
  let url = directory.appendingPathComponent("quadrants.heic")
  try writeImage(sourceImage, to: url, type: .heic, orientation: 1)
  let original = try Data(contentsOf: url)
  let input = try inspectInput(at: url)
  try imageCheck(
    input.record.asset.typeIdentifier == UTType.heic.identifier
      || input.record.asset.typeIdentifier == UTType.heif.identifier,
    "HEIC inspection returned the wrong type identifier.")
  try assertPageSize(input, width: 120, height: 80, label: "HEIC")
  let page = try imageRequire(input.record.pages.first, "The HEIC page is missing.")
  let rendered = try DocumentRenderer.renderPage(input: input, pageID: page.id, scale: 1)
  try assertQuadrants(
    rendered.image,
    expected: [.red, .green, .blue, .yellow],
    tolerance: 0.28,
    label: "HEIC")
  try imageCheck(
    try Data(contentsOf: url) == original,
    "HEIC inspection or rendering modified the original bytes.")
}

private func inspectInput(at url: URL) throws -> DocumentInput {
  let inspection = try DocumentInspector.inspect(url: url)
  let bytes = try Data(contentsOf: url)
  let asset = AssetReference(
    sha256: "synthetic-\(url.lastPathComponent)",
    byteCount: Int64(bytes.count),
    typeIdentifier: inspection.typeIdentifier,
    relativePath: url.lastPathComponent)
  return DocumentInput(
    record: SourceDocumentRecord(
      originalName: url.lastPathComponent, asset: asset, pages: inspection.pages),
    url: url)
}

private func makeQuadrantImage(width: Int, height: Int) throws -> CGImage {
  var pixels = [UInt8](repeating: 255, count: width * height * 4)
  for y in 0..<height {
    for x in 0..<width {
      let color: (UInt8, UInt8, UInt8)
      switch (x < width / 2, y < height / 2) {
      case (true, true): color = (235, 26, 26)
      case (false, true): color = (26, 220, 46)
      case (true, false): color = (26, 61, 230)
      case (false, false): color = (235, 220, 26)
      }
      let offset = (y * width + x) * 4
      pixels[offset] = color.0
      pixels[offset + 1] = color.1
      pixels[offset + 2] = color.2
      pixels[offset + 3] = 255
    }
  }
  let payload = Data(pixels) as CFData
  guard let provider = CGDataProvider(data: payload),
    let image = CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent)
  else { throw ImageWorkflowCheckFailure(description: "Synthetic CGImage creation failed.") }
  return image
}

private func writeImage(
  _ image: CGImage, to url: URL, type: UTType, orientation: Int
) throws {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, type.identifier as CFString, 1, nil)
  else {
    throw ImageWorkflowCheckFailure(
      description: "The runtime could not create a \(type.identifier) destination.")
  }
  let properties: [CFString: Any] = [
    kCGImagePropertyOrientation: orientation,
    kCGImagePropertyDPIWidth: 72,
    kCGImagePropertyDPIHeight: 72,
    kCGImageDestinationLossyCompressionQuality: 0.96,
  ]
  CGImageDestinationAddImage(destination, image, properties as CFDictionary)
  guard CGImageDestinationFinalize(destination) else {
    throw ImageWorkflowCheckFailure(
      description: "The runtime failed to encode \(type.identifier).")
  }
}

private func assertPageSize(
  _ input: DocumentInput, width: Double, height: Double, label: String
) throws {
  let page = try imageRequire(input.record.pages.first, "\(label) inspection created no page.")
  try imageCheck(
    abs(page.cropBox.width - width) < 0.01 && abs(page.cropBox.height - height) < 0.01,
    "\(label) inspection produced \(page.cropBox.width) by \(page.cropBox.height), expected \(width) by \(height)."
  )
}

/// Expected order is top-left, top-right, bottom-left, bottom-right.
private func assertQuadrants(
  _ image: CGImage, expected: [TestColor], tolerance: Double, label: String
) throws {
  try imageCheck(expected.count == 4, "The quadrant expectation is incomplete.")
  let points = [
    CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.25),
    CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.75, y: 0.75),
  ]
  for (index, point) in points.enumerated() {
    let sampled = try sample(
      image, x: Int(Double(image.width) * Double(point.x)),
      y: Int(Double(image.height) * Double(point.y)))
    try assertColor(
      sampled, near: expected[index], tolerance: tolerance,
      message: "\(label) rendered quadrant \(index + 1) has the wrong source pixels.")
  }
}

private func sampleCenter(_ image: CGImage) throws -> TestColor {
  try sample(image, x: image.width / 2, y: image.height / 2)
}

private func sample(_ image: CGImage, x: Int, y: Int) throws -> TestColor {
  let sampleSize = 5
  let sampleRect = CGRect(
    x: CGFloat(max(0, min(image.width - sampleSize, x - sampleSize / 2))),
    y: CGFloat(max(0, min(image.height - sampleSize, y - sampleSize / 2))),
    width: CGFloat(min(sampleSize, image.width)),
    height: CGFloat(min(sampleSize, image.height)))
  guard let cropped = image.cropping(to: sampleRect) else {
    throw ImageWorkflowCheckFailure(description: "A rendered pixel sample could not be cropped.")
  }
  var pixel = [UInt8](repeating: 0, count: 4)
  let didDraw = pixel.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let context = CGContext(
        data: buffer.baseAddress,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.interpolationQuality = .medium
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return true
  }
  guard didDraw else {
    throw ImageWorkflowCheckFailure(description: "A rendered pixel sample could not be read.")
  }
  return TestColor(
    red: Double(pixel[0]) / 255,
    green: Double(pixel[1]) / 255,
    blue: Double(pixel[2]) / 255)
}

private func assertColor(
  _ actual: TestColor, near expected: TestColor, tolerance: Double, message: String
) throws {
  let distance = sqrt(
    pow(actual.red - expected.red, 2)
      + pow(actual.green - expected.green, 2)
      + pow(actual.blue - expected.blue, 2))
  try imageCheck(distance <= tolerance, "\(message) Color distance was \(distance).")
}

private func imageRequire<T>(_ value: T?, _ message: String) throws -> T {
  guard let value else { throw ImageWorkflowCheckFailure(description: message) }
  return value
}

private func imageCheck(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  guard try condition() else { throw ImageWorkflowCheckFailure(description: message) }
}
