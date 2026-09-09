import Foundation

public enum PointValueParseFailure: Error, Equatable, LocalizedError, Sendable {
  case empty
  case invalidFormat
  case tooManyDecimalPlaces
  case overflow

  public var errorDescription: String? {
    switch self {
    case .empty:
      return "Enter a point value."
    case .invalidFormat:
      return "Use digits with an optional decimal point."
    case .tooManyDecimalPlaces:
      return "Point values may have at most two decimal places."
    case .overflow:
      return "This point value is too large."
    }
  }
}

extension PointValue {
  public static func parse(_ text: String) throws -> PointValue {
    let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else { throw PointValueParseFailure.empty }

    var digits = source[...]
    var isNegative = false
    if digits.first == "+" {
      digits.removeFirst()
    } else if digits.first == "-" {
      isNegative = true
      digits.removeFirst()
    }
    guard !digits.isEmpty else { throw PointValueParseFailure.invalidFormat }

    let components = digits.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count <= 2, let wholeText = components.first,
      wholeText.allSatisfy(\.isNumber)
    else {
      throw PointValueParseFailure.invalidFormat
    }

    let fractionText = components.count == 2 ? components[1] : Substring()
    guard !wholeText.isEmpty || !fractionText.isEmpty else {
      throw PointValueParseFailure.invalidFormat
    }
    guard fractionText.count <= 2 else { throw PointValueParseFailure.tooManyDecimalPlaces }
    guard fractionText.allSatisfy(\.isNumber) else { throw PointValueParseFailure.invalidFormat }

    guard let whole = wholeText.isEmpty ? 0 : UInt64(wholeText) else {
      throw PointValueParseFailure.overflow
    }
    let paddedFraction = fractionText + String(repeating: "0", count: 2 - fractionText.count)
    guard let fraction = UInt64(paddedFraction) else { throw PointValueParseFailure.invalidFormat }
    let (scaledWhole, scaleOverflow) = whole.multipliedReportingOverflow(by: 100)
    let (magnitude, additionOverflow) = scaledWhole.addingReportingOverflow(fraction)
    guard !scaleOverflow, !additionOverflow else { throw PointValueParseFailure.overflow }

    let maximumMagnitude = UInt64(Int64.max) + (isNegative ? 1 : 0)
    guard magnitude <= maximumMagnitude else { throw PointValueParseFailure.overflow }
    if isNegative {
      if magnitude == UInt64(Int64.max) + 1 { return PointValue(Int64.min) }
      return PointValue(-Int64(magnitude))
    }
    return PointValue(Int64(magnitude))
  }
}
