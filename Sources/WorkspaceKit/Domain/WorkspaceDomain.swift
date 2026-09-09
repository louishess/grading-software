import Foundation

public struct PointValue: Codable, Hashable, Comparable, Sendable {
  public var hundredths: Int64
  public init(_ hundredths: Int64 = 0) { self.hundredths = hundredths }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.hundredths < rhs.hundredths }
  public var decimalString: String {
    let amount = Decimal(hundredths) / 100
    return NSDecimalNumber(decimal: amount).stringValue
  }
}

public struct PageRectangle: Codable, Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double
  public init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}
public struct PagePoint: Codable, Hashable, Sendable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}
public struct AssetReference: Codable, Hashable, Identifiable, Sendable {
  public var id: String { sha256 }
  public var sha256: String
  public var byteCount: Int64
  public var typeIdentifier: String
  public var relativePath: String
  public init(sha256: String, byteCount: Int64, typeIdentifier: String, relativePath: String) {
    self.sha256 = sha256
    self.byteCount = byteCount
    self.typeIdentifier = typeIdentifier
    self.relativePath = relativePath
  }
}
public struct DocumentPageRecord: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var index: Int
  public var mediaBox: PageRectangle
  public var cropBox: PageRectangle
  public var rotation: Int = 0
  public init(index: Int, mediaBox: PageRectangle, cropBox: PageRectangle, rotation: Int = 0) {
    self.index = index
    self.mediaBox = mediaBox
    self.cropBox = cropBox
    self.rotation = rotation
  }
}
public struct SourceDocumentRecord: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var revisionID: UUID = UUID()
  public var originalName: String
  public var asset: AssetReference
  public var pages: [DocumentPageRecord]
  public init(originalName: String, asset: AssetReference, pages: [DocumentPageRecord]) {
    self.originalName = originalName
    self.asset = asset
    self.pages = pages
  }
}
public struct PageRegion: Codable, Hashable, Sendable {
  public var coordinateVersion: Int = 1
  public var documentID: UUID
  public var documentRevisionID: UUID
  public var pageID: UUID
  public var bounds: PageRectangle
  public init(documentID: UUID, documentRevisionID: UUID, pageID: UUID, bounds: PageRectangle) {
    self.documentID = documentID
    self.documentRevisionID = documentRevisionID
    self.pageID = pageID
    self.bounds = bounds
  }
}
public enum MarkKind: String, Codable, CaseIterable, Sendable {
  case highlight, note, ink, displayMask
}
public struct DocumentMark: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var region: PageRegion
  public var kind: MarkKind
  public var text: String = ""
  public var points: [PagePoint] = []
  public var colorHex: String = "#E5AD31"
  public var lineWidth: Double = 2
  public var pencilDrawing: Data?
  public init(region: PageRegion, kind: MarkKind, text: String = "", points: [PagePoint] = []) {
    self.region = region
    self.kind = kind
    self.text = text
    self.points = points
  }
}
public enum TranscriptBlockKind: String, Codable, Sendable { case text, imageCrop }
public struct TranscriptBlock: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var region: PageRegion
  public var kind: TranscriptBlockKind
  public var observedText: String
  public var correction: String?
  public var confidence: Double?
  public var cropAsset: AssetReference?
  public init(
    region: PageRegion, kind: TranscriptBlockKind, observedText: String = "",
    confidence: Double? = nil
  ) {
    self.region = region
    self.kind = kind
    self.observedText = observedText
    self.confidence = confidence
  }
  public var displayText: String { correction ?? observedText }
}
public struct OCRRecord: Codable, Hashable, Sendable {
  public var revisionID: UUID = UUID()
  public var languages: [String] = ["en-US"]
  public var engine: String = "Vision"
  public var requestRevision: Int = 0
  public var createdAt: Date = Date()
  public var blocks: [TranscriptBlock] = []
  public init() {}
}
public struct WorkPart: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var title: String
  public init(title: String) { self.title = title }
}
public struct WorkCriterion: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var partID: UUID
  public var title: String
  public var guidance: String
  public var maximum: PointValue
  public init(partID: UUID, title: String, guidance: String = "", maximum: PointValue) {
    self.partID = partID
    self.title = title
    self.guidance = guidance
    self.maximum = maximum
  }
}
public struct ReferenceMaterial: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var partID: UUID
  public var title: String
  public var text: String
  public var document: SourceDocumentRecord?
  public init(partID: UUID, title: String, text: String = "", document: SourceDocumentRecord? = nil)
  {
    self.partID = partID
    self.title = title
    self.text = text
    self.document = document
  }
}
public enum ReviewStatus: String, Codable, CaseIterable, Sendable { case draft, reviewed, approved }
public struct ScoreEntry: Codable, Hashable, Sendable {
  public var value: PointValue
  public var confirmed: Bool
  public init(value: PointValue, confirmed: Bool = true) {
    self.value = value
    self.confirmed = confirmed
  }
}
public struct ReviewHistoryEntry: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var date: Date = Date()
  public var reviewRevisionID: UUID
  public var rubricRevisionID: UUID
  public var status: ReviewStatus
  public var scores: [UUID: ScoreEntry]
  public var feedback: String
  public var reason: String
  public init(
    reviewRevisionID: UUID, rubricRevisionID: UUID, status: ReviewStatus,
    scores: [UUID: ScoreEntry], feedback: String, reason: String
  ) {
    self.reviewRevisionID = reviewRevisionID
    self.rubricRevisionID = rubricRevisionID
    self.status = status
    self.scores = scores
    self.feedback = feedback
    self.reason = reason
  }
}
public struct WorkSubmission: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var candidateID: UUID = UUID()
  public var candidateAlias: String
  public var documents: [SourceDocumentRecord] = []
  public var marks: [DocumentMark] = []
  public var ocr: OCRRecord = OCRRecord()
  public var scores: [UUID: ScoreEntry] = [:]
  public var feedback: String = ""
  public var status: ReviewStatus = .draft
  public var reviewRevisionID: UUID = UUID()
  public var approvedReviewRevisionID: UUID?
  public var approvedRubricRevisionID: UUID?
  public var history: [ReviewHistoryEntry] = []
  public init(candidateAlias: String) { self.candidateAlias = candidateAlias }
}
public struct WorkAssignment: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var title: String
  public var course: String
  public var rubricRevisionID: UUID = UUID()
  public var parts: [WorkPart] = []
  public var criteria: [WorkCriterion] = []
  public var references: [ReferenceMaterial] = []
  public var submissions: [WorkSubmission] = []
  public init(title: String, course: String = "") {
    self.title = title
    self.course = course
  }
}
public struct CandidateIdentity: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID { candidateID }
  public var candidateID: UUID
  public var displayName: String
  public init(candidateID: UUID, displayName: String) {
    self.candidateID = candidateID
    self.displayName = displayName
  }
}
public struct WorkspaceData: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID = UUID()
  public var containerID: UUID = UUID()
  public var revisionID: UUID = UUID()
  public var parentRevisionID: UUID?
  public var schemaVersion: Int = 1
  public var title: String
  public var modifiedAt: Date = Date()
  public var assignments: [WorkAssignment] = []
  public var identities: [CandidateIdentity] = []
  public init(title: String) { self.title = title }
  public var assets: [AssetReference] {
    var all: [AssetReference] = []
    for assignment in assignments {
      all += assignment.references.compactMap { $0.document?.asset }
      for submission in assignment.submissions {
        all += submission.documents.map(\.asset)
        all += submission.ocr.blocks.compactMap(\.cropAsset)
      }
    }
    return Array(Dictionary(all.map { ($0.sha256, $0) }, uniquingKeysWith: { a, _ in a }).values)
  }
}
public struct WorkspaceSummary: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID { containerID }
  public var workspaceID: UUID
  public var containerID: UUID
  public var title: String
  public var modifiedAt: Date
  public init(_ data: WorkspaceData) {
    workspaceID = data.id
    containerID = data.containerID
    title = data.title
    modifiedAt = data.modifiedAt
  }
}
public struct WorkspaceImportResult: Sendable {
  public var workspace: WorkspaceData
  public var wasDuplicate: Bool
  public var isSeparateCopy: Bool
  public init(workspace: WorkspaceData, wasDuplicate: Bool, isSeparateCopy: Bool) {
    self.workspace = workspace
    self.wasDuplicate = wasDuplicate
    self.isSeparateCopy = isSeparateCopy
  }
}
public enum WorkspaceFailure: Error, LocalizedError, Sendable {
  case invalid(String)
  case staleRevision
  case unavailable(String)
  case cancelled
  public var errorDescription: String? {
    switch self {
    case .invalid(let message), .unavailable(let message): return message
    case .staleRevision: return "This workspace changed. Reload it before applying this edit."
    case .cancelled: return "The operation was cancelled."
    }
  }
}
