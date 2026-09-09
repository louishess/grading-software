import CoreGraphics
import Foundation
@preconcurrency import Vision

public enum DocumentOCR {
  public static func supportedLanguages() throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.revision = VNRecognizeTextRequestRevision3
    return try request.supportedRecognitionLanguages().sorted()
  }

  public static func recognize(
    input: DocumentInput,
    languages: [String] = ["en-US"]
  ) async throws -> OCRRecord {
    let supported = try supportedLanguages()
    let requested = languages.isEmpty ? ["en-US"] : languages
    let selected = requested.filter(supported.contains)
    guard !selected.isEmpty else {
      throw DocumentFailure.recognitionFailed("None of the selected languages is supported.")
    }

    var locatedBlocks: [LocatedBlock] = []
    for page in input.record.pages.sorted(by: { $0.index < $1.index }) {
      try Task.checkCancellation()
      let rendered = try DocumentRenderer.renderPage(input: input, pageID: page.id, scale: 2)
      let result = try await observations(in: rendered.image, languages: selected)
      try Task.checkCancellation()
      for observation in result.observations {
        guard let candidate = observation.topCandidates(1).first,
          !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { continue }
        do {
          let region = try DocumentGeometry.pageRegion(
            fromVisionNormalizedBounds: observation.boundingBox,
            input: input,
            page: page
          )
          let block = TranscriptBlock(
            region: region,
            kind: .text,
            observedText: candidate.string,
            confidence: Double(candidate.confidence)
          )
          locatedBlocks.append(
            LocatedBlock(
              pageIndex: page.index,
              displayBounds: observation.boundingBox,
              block: block
            ))
        } catch DocumentFailure.invalidRegion {
          continue
        }
      }
    }

    locatedBlocks.sort {
      if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
      if $0.displayBounds.maxY != $1.displayBounds.maxY {
        return $0.displayBounds.maxY > $1.displayBounds.maxY
      }
      if $0.displayBounds.minX != $1.displayBounds.minX {
        return $0.displayBounds.minX < $1.displayBounds.minX
      }
      return $0.block.id.uuidString < $1.block.id.uuidString
    }
    var record = OCRRecord()
    record.languages = selected
    record.requestRevision = VNRecognizeTextRequestRevision3
    record.blocks = locatedBlocks.map(\.block)
    return record
  }

  /// Preserves explicit teacher corrections when a rerun produces a substantially
  /// overlapping observation on the same source page.
  public static func mergingCorrections(
    from previous: OCRRecord,
    into rerun: OCRRecord,
    minimumOverlap: Double = 0.65
  ) -> OCRRecord {
    var merged = rerun
    for index in merged.blocks.indices where merged.blocks[index].kind == .text {
      let incoming = merged.blocks[index]
      let matches = previous.blocks.filter {
        $0.kind == .text && $0.correction != nil
          && $0.region.documentRevisionID == incoming.region.documentRevisionID
          && $0.region.pageID == incoming.region.pageID
      }
      guard
        let match = matches.max(by: {
          intersectionOverUnion($0.region.bounds, incoming.region.bounds)
            < intersectionOverUnion($1.region.bounds, incoming.region.bounds)
        }),
        intersectionOverUnion(match.region.bounds, incoming.region.bounds) >= minimumOverlap
      else { continue }
      merged.blocks[index].correction = match.correction
    }
    return merged
  }

  /// Returns conservative crop suggestions from weak or symbol-heavy OCR observations.
  /// These are review prompts, not detected equations; a teacher must confirm them.
  public static func suggestedCropRegions(
    in record: OCRRecord,
    confidenceBelow: Double = 0.65
  ) -> [PageRegion] {
    record.blocks.compactMap { block in
      guard block.kind == .text else { return nil }
      let text = block.observedText
      let symbols = text.filter { "=+-×÷*/^√∫Σ()[]{}<>≤≥≈0123456789".contains($0) }.count
      let nonspace = max(1, text.filter { !$0.isWhitespace }.count)
      let symbolRatio = Double(symbols) / Double(nonspace)
      let lowConfidence = (block.confidence ?? 1) < confidenceBelow
      return lowConfidence || (symbols >= 2 && symbolRatio >= 0.3) ? block.region : nil
    }
  }

  public static func imageCropBlock(from block: TranscriptBlock) -> TranscriptBlock {
    var crop = TranscriptBlock(region: block.region, kind: .imageCrop)
    crop.id = block.id
    return crop
  }

  private static func observations(
    in image: CGImage,
    languages: [String]
  ) async throws -> (observations: [VNRecognizedTextObservation], revision: Int) {
    let requestBox = RecognitionRequestBox()
    let request = requestBox.request
    request.recognitionLevel = .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = true
    request.revision = VNRecognizeTextRequestRevision3
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    return try await withTaskCancellationHandler {
      do {
        try Task.checkCancellation()
        try handler.perform([request])
        try Task.checkCancellation()
        return (request.results ?? [], request.revision)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw DocumentFailure.recognitionFailed(error.localizedDescription)
      }
    } onCancel: {
      requestBox.request.cancel()
    }
  }

  private static func intersectionOverUnion(
    _ lhs: PageRectangle,
    _ rhs: PageRectangle
  ) -> Double {
    let left = lhs.cgRect
    let right = rhs.cgRect
    let intersection = left.intersection(right)
    guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
    let intersectionArea = intersection.width * intersection.height
    let unionArea = left.width * left.height + right.width * right.height - intersectionArea
    return unionArea > 0 ? Double(intersectionArea / unionArea) : 0
  }

  private struct LocatedBlock {
    var pageIndex: Int
    var displayBounds: CGRect
    var block: TranscriptBlock
  }

  private final class RecognitionRequestBox: @unchecked Sendable {
    let request = VNRecognizeTextRequest()
  }
}
