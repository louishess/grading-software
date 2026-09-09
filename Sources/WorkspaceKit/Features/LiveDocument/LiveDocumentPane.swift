import Foundation
import PDFKit
import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import PencilKit
  import UIKit
#endif

public struct LiveDocumentPane: View {
  private let input: DocumentInput?
  private let marks: [DocumentMark]
  private let masked: Bool
  private let readOnly: Bool
  private let focusedRegion: PageRegion?
  private let onAddMark: (DocumentMark) -> Void
  private let onCrop: (PageRegion) -> Void
  private let onRemoveMark: (UUID) -> Void

  @State private var selectedTool: LiveDocumentTool = .pointer
  @State private var pageIndex = 0
  @State private var zoom = 1.0
  @State private var noteDraft: LiveNoteDraft?
  @State private var localMarkIDs: [UUID] = []
  @State private var marksPopoverPresented = false

  public init(
    input: DocumentInput?,
    marks: [DocumentMark],
    masked: Bool,
    readOnly: Bool,
    focusedRegion: PageRegion?,
    onAddMark: @escaping (DocumentMark) -> Void,
    onCrop: @escaping (PageRegion) -> Void,
    onRemoveMark: @escaping (UUID) -> Void
  ) {
    self.input = input
    self.marks = marks
    self.masked = masked
    self.readOnly = readOnly
    self.focusedRegion = focusedRegion
    self.onAddMark = onAddMark
    self.onCrop = onCrop
    self.onRemoveMark = onRemoveMark
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      reader
    }
    .background(WorkspaceStyle.background)
    .foregroundStyle(WorkspaceStyle.ink)
    .onAppear {
      clampPageIndex()
    }
    .onChange(of: input?.record.id) { _, _ in
      pageIndex = 0
      zoom = 1
      localMarkIDs = []
      noteDraft = nil
      marksPopoverPresented = false
    }
    .onChange(of: input?.record.revisionID) { _, _ in
      pageIndex = 0
      zoom = 1
      localMarkIDs = []
      noteDraft = nil
      marksPopoverPresented = false
    }
    .onChange(of: input?.record.pages.count) { _, _ in
      clampPageIndex()
    }
    .sheet(item: $noteDraft) { draft in
      LiveNoteEditor(
        onCommit: { text in
          commitNote(text, draft: draft)
        },
        onCancel: {
          noteDraft = nil
        })
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(documentTitle)
            .font(.headline)
          if let toolbarSubtitle {
            Text(toolbarSubtitle)
              .font(.caption)
              .foregroundStyle(WorkspaceStyle.secondary)
          }
        }
        Spacer(minLength: 8)
        if masked {
          Label("Display masking", systemImage: "eye.slash")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .accessibilityHint("Masks are visual only and are never exported as redactions.")
        }
      }

      ViewThatFits(in: .horizontal) {
        fullControls
        compactControls
      }

      if editingUnavailable {
        Label(editingUnavailableMessage, systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .accessibilityElement(children: .combine)
      } else if selectedTool != .pointer {
        Label(selectedTool.instruction, systemImage: selectedTool.systemImage)
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .accessibilityElement(children: .combine)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(WorkspaceStyle.surface)
  }

  @ViewBuilder
  private var reader: some View {
    if let input {
      LivePDFReader(
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        focusedRegion: focusedRegion,
        pageIndex: $pageIndex,
        zoom: $zoom,
        tool: selectedTool,
        onGesture: receive(_:from:)
      )
      .id(input.record.revisionID)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay(alignment: .topLeading) {
        if masked {
          Text("Visual masks are display-only")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.72), in: Capsule())
            .padding(10)
            .accessibilityHint("Masks are not annotation marks and are excluded from exports.")
        }
      }
    } else {
      ContentUnavailableView {
        Label("No document selected", systemImage: "doc")
      } description: {
        Text("Choose a PDF or image document to review it here.")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(WorkspaceStyle.inset)
    }
  }

  private var pageCount: Int {
    input?.record.pages.count ?? 0
  }

  private var documentTitle: String {
    if masked { return "Document" }
    return input?.record.originalName ?? "Document reader"
  }

  private var fullControls: some View {
    HStack(spacing: 6) {
      toolButtons
      Divider()
        .frame(height: 20)
      pageControls
      Divider()
        .frame(height: 20)
      zoomControls
      Spacer(minLength: 4)
      marksButton
      undoButton
    }
  }

  private var compactControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 72), spacing: 5)],
        alignment: .leading,
        spacing: 5
      ) {
        toolButtons
      }
      HStack(spacing: 7) {
        pageControls
        Spacer(minLength: 4)
        zoomControls
        marksButton
        undoButton
      }
    }
  }

  private var toolButtons: some View {
    ForEach(LiveDocumentTool.allCases) { tool in
      Button {
        selectedTool = tool
      } label: {
        Label(tool.title, systemImage: tool.systemImage)
          .labelStyle(.titleAndIcon)
          .font(.caption.weight(.medium))
      }
      .buttonStyle(.bordered)
      .tint(selectedTool == tool ? WorkspaceStyle.accent : WorkspaceStyle.secondary)
      .controlSize(.small)
      .disabled(tool != .pointer && editingUnavailable)
      .help(tool.help)
      .accessibilityLabel(tool.title)
    }
  }

  private var pageControls: some View {
    HStack(spacing: 5) {
      Button {
        pageIndex = max(0, pageIndex - 1)
      } label: {
        Image(systemName: "chevron.left")
      }
      .buttonStyle(.borderless)
      .disabled(pageIndex == 0 || pageCount == 0)
      .accessibilityLabel("Previous page")

      Text(pageCount == 0 ? "No pages" : "Page \(min(pageIndex + 1, pageCount)) of \(pageCount)")
        .font(.caption.monospacedDigit())
        .frame(minWidth: 78)
        .accessibilityLabel(pageCount == 0 ? "No pages" : "Page \(pageIndex + 1) of \(pageCount)")

      Button {
        pageIndex = min(max(0, pageCount - 1), pageIndex + 1)
      } label: {
        Image(systemName: "chevron.right")
      }
      .buttonStyle(.borderless)
      .disabled(pageIndex >= pageCount - 1 || pageCount == 0)
      .accessibilityLabel("Next page")
    }
  }

  private var zoomControls: some View {
    HStack(spacing: 4) {
      Button {
        zoom = max(0.4, zoom - 0.1)
      } label: {
        Image(systemName: "minus.magnifyingglass")
      }
      .buttonStyle(.borderless)
      .disabled(input == nil || zoom <= 0.4)
      .accessibilityLabel("Zoom out")

      Text("\(Int(zoom * 100))%")
        .font(.caption.monospacedDigit())
        .frame(width: 38)
        .accessibilityLabel("Zoom \(Int(zoom * 100)) percent")

      Button {
        zoom = min(4, zoom + 0.1)
      } label: {
        Image(systemName: "plus.magnifyingglass")
      }
      .buttonStyle(.borderless)
      .disabled(input == nil || zoom >= 4)
      .accessibilityLabel("Zoom in")
    }
  }

  private var undoButton: some View {
    Button {
      undoLastMark()
    } label: {
      Label("Undo", systemImage: "arrow.uturn.backward")
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .disabled(editingUnavailable || localMarkIDs.isEmpty)
    .help("Remove the last mark created in this reader session")
  }

  private var marksButton: some View {
    Button {
      marksPopoverPresented = true
    } label: {
      Label("Marks \(currentPageMarks.count)", systemImage: "list.bullet.rectangle")
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .disabled(input == nil)
    .help("Review or remove saved marks on the current page")
    .popover(isPresented: $marksPopoverPresented, arrowEdge: .bottom) {
      LivePersistedMarkList(
        marks: currentPageMarks,
        masked: masked,
        canRemove: !readOnly,
        onRemove: removePersistedMark
      )
    }
  }

  private var editingUnavailable: Bool {
    readOnly || input == nil || isPhone
  }

  private var editingUnavailableMessage: String {
    if readOnly { return "Review-only mode: marks and crops are disabled." }
    if isPhone { return "iPhone review mode: use a larger device to add marks or crops." }
    return "Select a document before adding marks or crops."
  }

  private var toolbarSubtitle: String? {
    if input == nil { return "Select a source document to begin." }
    if readOnly { return "Review-only source" }
    return nil
  }

  private var isPhone: Bool {
    #if os(iOS)
      return UIDevice.current.userInterfaceIdiom == .phone
    #else
      return false
    #endif
  }

  private func clampPageIndex() {
    pageIndex = min(max(0, pageIndex), max(0, pageCount - 1))
  }

  private func undoLastMark() {
    guard let id = localMarkIDs.popLast() else { return }
    onRemoveMark(id)
  }

  private func removePersistedMark(_ id: UUID) {
    localMarkIDs.removeAll { $0 == id }
    onRemoveMark(id)
  }

  private var currentPageMarks: [DocumentMark] {
    guard let input,
      let page = input.record.pages.first(where: { $0.index == pageIndex })
    else { return [] }
    return marks.filter {
      $0.region.documentID == input.record.id
        && $0.region.documentRevisionID == input.record.revisionID
        && $0.region.pageID == page.id
    }
  }

  private func receive(_ gesture: LiveDocumentPageGesture, from page: PDFPage) {
    guard let input else { return }
    guard
      let pageRecord = input.record.pages.first(where: {
        $0.index == pageIndex(for: page, input: input)
      })
    else { return }

    switch gesture {
    case .crop(let points):
      guard
        let region = LiveDocumentGeometry.region(
          from: points,
          input: input,
          page: pageRecord,
          margin: 0
        )
      else { return }
      onCrop(region)

    case .note(let point):
      guard
        let region = LiveDocumentGeometry.region(
          from: [point],
          input: input,
          page: pageRecord,
          margin: 8
        )
      else { return }
      noteDraft = LiveNoteDraft(
        region: region,
        point: PagePoint(x: point.x, y: point.y)
      )

    case .highlight(let points):
      guard
        let result = LiveDocumentGeometry.regionAndPoints(
          from: points,
          input: input,
          page: pageRecord,
          margin: 0.5
        )
      else { return }
      var mark = DocumentMark(
        region: result.region,
        kind: .highlight,
        points: result.points
      )
      mark.colorHex = "#E5AD31"
      mark.lineWidth = 1
      onAddMark(mark)
      localMarkIDs.append(mark.id)

    case .ink(
      let points,
      let drawingData,
      let pencilContentVersion,
      let pencilCanvasTransform
    ):
      guard !points.isEmpty,
        let result = LiveDocumentGeometry.regionAndPoints(
          from: points,
          input: input,
          page: pageRecord,
          margin: 2
        )
      else { return }
      var mark = DocumentMark(
        region: result.region,
        kind: .ink,
        points: result.points
      )
      mark.colorHex = "#2C6BED"
      mark.lineWidth = 2
      mark.pencilDrawing = drawingData
      mark.pencilContentVersion = pencilContentVersion
      mark.pencilCanvasTransform = pencilCanvasTransform
      onAddMark(mark)
      localMarkIDs.append(mark.id)

    case .mask(let points):
      guard
        let result = LiveDocumentGeometry.regionAndPoints(
          from: points,
          input: input,
          page: pageRecord,
          margin: 0
        )
      else { return }
      var mark = DocumentMark(
        region: result.region,
        kind: .displayMask,
        points: result.points
      )
      mark.colorHex = "#000000"
      mark.lineWidth = 0
      onAddMark(mark)
      localMarkIDs.append(mark.id)
    }
  }

  private func pageIndex(for page: PDFPage, input: DocumentInput) -> Int {
    guard let document = page.document else { return -1 }
    return document.index(for: page)
  }

  private func commitNote(_ text: String, draft: LiveNoteDraft) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      noteDraft = nil
      return
    }
    var mark = DocumentMark(
      region: draft.region,
      kind: .note,
      text: trimmed,
      points: [draft.point]
    )
    mark.colorHex = "#2C6BED"
    mark.lineWidth = 1
    onAddMark(mark)
    localMarkIDs.append(mark.id)
    noteDraft = nil
  }
}

private enum LiveDocumentTool: String, CaseIterable, Identifiable {
  case pointer
  case highlight
  case note
  case ink
  case crop
  case mask

  var id: String { rawValue }

  var title: String {
    switch self {
    case .pointer: return "Select"
    case .highlight: return "Highlight"
    case .note: return "Note"
    case .ink: return "Ink"
    case .crop: return "Crop"
    case .mask: return "Mask"
    }
  }

  var systemImage: String {
    switch self {
    case .pointer: return "arrow"
    case .highlight: return "highlighter"
    case .note: return "text.bubble"
    case .ink: return "pencil.tip"
    case .crop: return "crop"
    case .mask: return "rectangle.slash"
    }
  }

  var instruction: String {
    switch self {
    case .pointer: return "Select text or scroll the page."
    case .highlight: return "Drag over the response to add one highlight."
    case .note: return "Click or tap where the note belongs, then enter its text."
    case .ink: return "Draw a freehand mark; lift the pointer or Pencil to save it."
    case .crop: return "Drag a page region to send it to the source crop workflow."
    case .mask: return "Drag a region to cover it with an opaque display-only mask."
    }
  }

  var help: String {
    switch self {
    case .pointer: return "Review and select document content"
    case .highlight: return "Drag to add a highlight mark"
    case .note: return "Place a text note"
    case .ink: return "Draw freehand ink"
    case .crop: return "Select a region for the crop workflow"
    case .mask: return "Cover a region with an opaque display-only mask"
    }
  }
}

extension MarkKind {
  fileprivate var title: String {
    switch self {
    case .highlight: return "Highlight"
    case .note: return "Text note"
    case .ink: return "Ink"
    case .displayMask: return "Display mask"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .highlight: return "highlighter"
    case .note: return "text.bubble"
    case .ink: return "pencil.tip"
    case .displayMask: return "rectangle.slash"
    }
  }
}

private struct LiveNoteDraft: Identifiable {
  let id = UUID()
  let region: PageRegion
  let point: PagePoint
}

private struct LiveNoteEditor: View {
  @State private var text = ""
  let onCommit: (String) -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Add text note")
        .font(.headline)
      TextEditor(text: $text)
        .frame(minWidth: 300, minHeight: 100)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border))
        .accessibilityLabel("Note text")
      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
        Button("Add note") {
          onCommit(text)
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkspaceStyle.accent)
      }
    }
    .padding(20)
  }
}

private struct LivePersistedMarkList: View {
  let marks: [DocumentMark]
  let masked: Bool
  let canRemove: Bool
  let onRemove: (UUID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Saved marks", systemImage: "list.bullet.rectangle")
          .font(.headline)
        Spacer()
        Text("\(marks.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(WorkspaceStyle.secondary)
      }

      if marks.isEmpty {
        Text("No marks on this page.")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(marks) { mark in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: mark.kind.systemImage)
                  .foregroundStyle(mark.kind == .displayMask ? .black : WorkspaceStyle.accent)
                  .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                  Text(mark.kind.title)
                    .font(.caption.weight(.semibold))
                  if mark.kind == .note {
                    Text(
                      masked
                        ? "Note text hidden by display mask."
                        : (mark.text.isEmpty ? "Empty note" : mark.text)
                    )
                    .font(.caption)
                    .foregroundStyle(WorkspaceStyle.secondary)
                    .lineLimit(3)
                  } else if mark.kind == .displayMask {
                    Text("Opaque visual cover; never exported as a redaction.")
                      .font(.caption2)
                      .foregroundStyle(WorkspaceStyle.secondary)
                  }
                }
                Spacer(minLength: 4)
                Button("Remove") {
                  onRemove(mark.id)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(!canRemove)
                .help(canRemove ? "Remove this saved mark" : "Review-only mode")
              }
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
            }
          }
        }
        .frame(maxHeight: 260)
      }

      if !canRemove {
        Text("Review-only mode: remove is disabled.")
          .font(.caption2)
          .foregroundStyle(WorkspaceStyle.secondary)
      }
    }
    .padding(14)
    .frame(minWidth: 250, idealWidth: 300, maxWidth: 340)
  }
}

private enum LiveDocumentGeometry {
  struct Result {
    let region: PageRegion
    let points: [PagePoint]
  }

  static func regionAndPoints(
    from points: [CGPoint],
    input: DocumentInput,
    page: DocumentPageRecord,
    margin: CGFloat
  ) -> Result? {
    let clamped = points.map { clamp($0, to: page.cropBox.cgRect) }
    guard !clamped.isEmpty else { return nil }
    let rect = paddedBounds(for: clamped, margin: margin, within: page.cropBox.cgRect)
    guard rect.width > 0, rect.height > 0 else { return nil }
    let region = PageRegion(
      documentID: input.record.id,
      documentRevisionID: input.record.revisionID,
      pageID: page.id,
      bounds: PageRectangle(rect)
    )
    return Result(
      region: region,
      points: clamped.map { PagePoint(x: $0.x, y: $0.y) }
    )
  }

  static func region(
    from points: [CGPoint],
    input: DocumentInput,
    page: DocumentPageRecord,
    margin: CGFloat
  ) -> PageRegion? {
    regionAndPoints(from: points, input: input, page: page, margin: margin)?.region
  }

  private static func paddedBounds(for points: [CGPoint], margin: CGFloat, within page: CGRect)
    -> CGRect
  {
    var minimumX = points[0].x
    var maximumX = points[0].x
    var minimumY = points[0].y
    var maximumY = points[0].y
    for point in points.dropFirst() {
      minimumX = min(minimumX, point.x)
      maximumX = max(maximumX, point.x)
      minimumY = min(minimumY, point.y)
      maximumY = max(maximumY, point.y)
    }
    var rect = CGRect(
      x: minimumX - margin,
      y: minimumY - margin,
      width: max(0.5, maximumX - minimumX + margin * 2),
      height: max(0.5, maximumY - minimumY + margin * 2)
    )
    if rect.width > page.width { rect.size.width = page.width }
    if rect.height > page.height { rect.size.height = page.height }
    rect.origin.x = min(max(rect.origin.x, page.minX), page.maxX - rect.width)
    rect.origin.y = min(max(rect.origin.y, page.minY), page.maxY - rect.height)
    return rect.intersection(page)
  }

  private static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
    CGPoint(
      x: min(max(point.x, rect.minX), rect.maxX),
      y: min(max(point.y, rect.minY), rect.maxY)
    )
  }
}

private enum LiveDocumentPageGesture {
  case highlight([CGPoint])
  case note(CGPoint)
  case ink(
    points: [CGPoint],
    drawingData: Data?,
    pencilContentVersion: Int?,
    pencilCanvasTransform: [Double]?
  )
  case crop([CGPoint])
  case mask([CGPoint])
}

private typealias LiveDocumentGestureHandler = @MainActor (LiveDocumentPageGesture, PDFPage) -> Void
private typealias LivePageIndexHandler = @MainActor @Sendable (Int) -> Void
private typealias LiveZoomHandler = @MainActor @Sendable (Double) -> Void

private struct LivePDFReader: View {
  let input: DocumentInput
  let marks: [DocumentMark]
  let masked: Bool
  let readOnly: Bool
  let focusedRegion: PageRegion?
  @Binding var pageIndex: Int
  @Binding var zoom: Double
  let tool: LiveDocumentTool
  let onGesture: LiveDocumentGestureHandler

  var body: some View {
    #if os(macOS)
      LiveMacPDFView(
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        focusedRegion: focusedRegion,
        pageIndex: $pageIndex,
        zoom: $zoom,
        tool: tool,
        onGesture: onGesture
      )
    #elseif os(iOS)
      LiveIOSPDFView(
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        focusedRegion: focusedRegion,
        pageIndex: $pageIndex,
        zoom: $zoom,
        tool: tool,
        onGesture: onGesture
      )
    #else
      Text("This platform does not provide a PDF reader.")
    #endif
  }
}

#if os(macOS)
  private struct LiveMacPDFView: NSViewRepresentable {
    let input: DocumentInput
    let marks: [DocumentMark]
    let masked: Bool
    let readOnly: Bool
    let focusedRegion: PageRegion?
    @Binding var pageIndex: Int
    @Binding var zoom: Double
    let tool: LiveDocumentTool
    let onGesture: LiveDocumentGestureHandler

    func makeCoordinator() -> Coordinator {
      .init()
    }

    func makeNSView(context: Context) -> PDFView {
      let view = PDFView(frame: .zero)
      view.translatesAutoresizingMaskIntoConstraints = false
      view.displayMode = .singlePageContinuous
      view.displayDirection = .vertical
      view.displayBox = .cropBox
      view.displaysPageBreaks = true
      view.pageBreakMargins = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
      view.backgroundColor = NSColor.windowBackgroundColor
      view.autoScales = false
      view.minScaleFactor = 0.4
      view.maxScaleFactor = 4
      context.coordinator.attach(
        view,
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        focusedRegion: focusedRegion,
        pageIndex: pageIndex,
        zoom: zoom,
        tool: tool,
        onGesture: onGesture,
        setPageIndex: { pageIndex = $0 },
        setZoom: { zoom = $0 }
      )
      return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
      context.coordinator.update(
        view,
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        focusedRegion: focusedRegion,
        pageIndex: pageIndex,
        zoom: zoom,
        tool: tool,
        onGesture: onGesture,
        setPageIndex: { pageIndex = $0 },
        setZoom: { zoom = $0 }
      )
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
      coordinator.detach(view)
    }

    @MainActor
    final class Coordinator: NSObject {
      private weak var view: PDFView?
      private var document: PDFDocument?
      private var inputSignature: LiveDocumentInputSignature?
      private var lastFocusedRegion: PageRegion?
      private var provider: LiveMacPageOverlayProvider?
      private var observers: [NSObjectProtocol] = []
      private var setPageIndex: LivePageIndexHandler?
      private var setZoom: LiveZoomHandler?

      func attach(
        _ view: PDFView,
        input: DocumentInput,
        marks: [DocumentMark],
        masked: Bool,
        readOnly: Bool,
        focusedRegion: PageRegion?,
        pageIndex: Int,
        zoom: Double,
        tool: LiveDocumentTool,
        onGesture: @escaping LiveDocumentGestureHandler,
        setPageIndex: @escaping LivePageIndexHandler,
        setZoom: @escaping LiveZoomHandler
      ) {
        self.view = view
        self.setPageIndex = setPageIndex
        self.setZoom = setZoom
        installObservers(on: view)
        update(
          view,
          input: input,
          marks: marks,
          masked: masked,
          readOnly: readOnly,
          focusedRegion: focusedRegion,
          pageIndex: pageIndex,
          zoom: zoom,
          tool: tool,
          onGesture: onGesture,
          setPageIndex: setPageIndex,
          setZoom: setZoom
        )
      }

      func update(
        _ view: PDFView,
        input: DocumentInput,
        marks: [DocumentMark],
        masked: Bool,
        readOnly: Bool,
        focusedRegion: PageRegion?,
        pageIndex: Int,
        zoom: Double,
        tool: LiveDocumentTool,
        onGesture: @escaping LiveDocumentGestureHandler,
        setPageIndex: @escaping LivePageIndexHandler,
        setZoom: @escaping LiveZoomHandler
      ) {
        self.view = view
        self.setPageIndex = setPageIndex
        self.setZoom = setZoom
        let signature = LiveDocumentInputSignature(input: input)
        if inputSignature != signature {
          provider?.flushAll()
          view.pageOverlayViewProvider = nil
          view.document = nil
          document = nil
          view.isInMarkupMode = true
          let loadedDocument = LivePDFDocumentLoader.load(input: input)
          let nextProvider = LiveMacPageOverlayProvider(
            input: input,
            marks: marks,
            masked: masked,
            readOnly: readOnly,
            tool: tool,
            onGesture: onGesture
          )
          provider = nextProvider
          view.pageOverlayViewProvider = nextProvider
          document = loadedDocument
          view.document = loadedDocument
          inputSignature = signature
        } else {
          provider?.update(
            input: input,
            marks: marks,
            masked: masked,
            readOnly: readOnly,
            tool: tool,
            onGesture: onGesture
          )
        }
        view.isInMarkupMode = true
        guard let document, document.pageCount > 0 else { return }
        let boundedPage = min(max(0, pageIndex), document.pageCount - 1)
        if let currentPage = view.currentPage,
          document.index(for: currentPage) != boundedPage,
          let destinationPage = document.page(at: boundedPage)
        {
          view.go(to: destinationPage)
        } else if view.currentPage == nil, let destinationPage = document.page(at: boundedPage) {
          view.go(to: destinationPage)
        }
        let boundedZoom = min(max(0.4, zoom), 4)
        if abs(view.scaleFactor - boundedZoom) > 0.001 {
          view.scaleFactor = boundedZoom
        }
        focus(
          focusedRegion,
          input: input,
          document: document,
          in: view
        )
      }

      func detach(_ view: PDFView) {
        provider?.flushAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        view.pageOverlayViewProvider = nil
        view.document = nil
        provider = nil
        document = nil
        lastFocusedRegion = nil
        self.view = nil
        setPageIndex = nil
        setZoom = nil
      }

      private func installObservers(
        on view: PDFView
      ) {
        let center = NotificationCenter.default
        observers.append(
          center.addObserver(
            forName: .PDFViewPageChanged,
            object: view,
            queue: .main
          ) { [weak self] _ in
            Task { @MainActor [weak self] in
              guard let self, let view = self.view,
                let page = view.currentPage, let document = view.document
              else {
                return
              }
              self.provider?.flushAll()
              self.setPageIndex?(document.index(for: page))
            }
          })
        observers.append(
          center.addObserver(
            forName: .PDFViewScaleChanged,
            object: view,
            queue: .main
          ) { [weak self] _ in
            Task { @MainActor [weak self] in
              guard let self, let view = self.view else { return }
              self.provider?.refreshAll()
              self.setZoom?(Double(view.scaleFactor))
            }
          })
      }

      private func focus(
        _ region: PageRegion?,
        input: DocumentInput,
        document: PDFDocument,
        in view: PDFView
      ) {
        guard region != lastFocusedRegion,
          let region,
          let pageRecord = input.record.pages.first(where: { $0.id == region.pageID }),
          let page = document.page(at: pageRecord.index),
          (try? DocumentGeometry.validate(region, input: input)) != nil
        else { return }
        view.go(to: region.bounds.cgRect, on: page)
        lastFocusedRegion = region
      }
    }
  }

  @MainActor
  private final class LiveMacPageOverlayProvider: NSObject,
    @preconcurrency PDFPageOverlayViewProvider
  {
    private var input: DocumentInput
    private var marks: [DocumentMark]
    private var masked: Bool
    private var readOnly: Bool
    private var tool: LiveDocumentTool
    private var onGesture: LiveDocumentGestureHandler
    private weak var pdfView: PDFView?
    private var overlays: [ObjectIdentifier: LiveMacPageOverlayView] = [:]

    init(
      input: DocumentInput,
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.input = input
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
    }

    func update(
      input: DocumentInput,
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.input = input
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
      for overlay in overlays.values {
        overlay.update(
          marks: marks,
          masked: masked,
          readOnly: readOnly,
          tool: tool,
          onGesture: onGesture
        )
      }
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
      pdfView = view
      let key = ObjectIdentifier(page)
      if let overlay = overlays[key] { return overlay }
      let overlay = LiveMacPageOverlayView(
        frame: .zero,
        pdfView: view,
        page: page,
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        tool: tool,
        onGesture: onGesture
      )
      overlays[key] = overlay
      return overlay
    }

    func pdfView(
      _ pdfView: PDFView,
      willEndDisplayingOverlayView overlayView: NSView,
      for page: PDFPage
    ) {
      (overlayView as? LiveMacPageOverlayView)?.flush()
      overlays.removeValue(forKey: ObjectIdentifier(page))
    }

    func flushAll() {
      for overlay in overlays.values {
        overlay.flush()
      }
    }

    func refreshAll() {
      for overlay in overlays.values {
        overlay.needsLayout = true
        overlay.needsDisplay = true
      }
    }
  }

  @MainActor
  private final class LiveMacPageOverlayView: NSView {
    private weak var pdfView: PDFView?
    private let page: PDFPage
    private let input: DocumentInput
    private var marks: [DocumentMark]
    private var masked: Bool
    private var readOnly: Bool
    private var tool: LiveDocumentTool
    private var onGesture: LiveDocumentGestureHandler
    private var trackingPoints: [CGPoint] = []
    private var tracking = false

    init(
      frame frameRect: NSRect,
      pdfView: PDFView,
      page: PDFPage,
      input: DocumentInput,
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.pdfView = pdfView
      self.page = page
      self.input = input
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
      super.init(frame: frameRect)
      autoresizingMask = [.width, .height]
      wantsLayer = true
      layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func update(
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
      needsLayout = true
      needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard !readOnly, tool != .pointer else { return nil }
      return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }

    override func mouseDown(with event: NSEvent) {
      guard !readOnly, tool != .pointer else { return }
      let point = convert(event.locationInWindow, from: nil)
      tracking = true
      trackingPoints = [point]
      needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
      guard tracking else { return }
      let point = convert(event.locationInWindow, from: nil)
      if trackingPoints.last.map({ distance($0, point) > 0.5 }) ?? true {
        trackingPoints.append(point)
        needsDisplay = true
      }
    }

    override func mouseUp(with event: NSEvent) {
      guard tracking else { return }
      let point = convert(event.locationInWindow, from: nil)
      if trackingPoints.last.map({ distance($0, point) > 0.5 }) ?? true {
        trackingPoints.append(point)
      }
      finishGesture()
    }

    func flush() {
      guard tracking else { return }
      finishGesture()
    }

    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)
      guard let context = NSGraphicsContext.current?.cgContext else { return }
      for mark in visibleMarks {
        draw(mark: mark, in: context)
      }
      drawPreview(in: context)
    }

    private var visibleMarks: [DocumentMark] {
      marks.filter { mark in
        guard mark.region.documentID == input.record.id,
          mark.region.documentRevisionID == input.record.revisionID,
          mark.region.pageID == pageRecord?.id
        else { return false }
        guard masked || mark.kind != .displayMask else { return false }
        return true
      }
    }

    private var pageRecord: DocumentPageRecord? {
      guard let document = page.document else { return nil }
      let index = document.index(for: page)
      return input.record.pages.first(where: { $0.index == index })
    }

    private func draw(mark: DocumentMark, in context: CGContext) {
      let rect = localRect(for: mark.region.bounds.cgRect)
      switch mark.kind {
      case .displayMask:
        context.setFillColor(NSColor.black.cgColor)
        context.fill(rect)
      case .highlight:
        context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.30).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.75).cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
      case .note:
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
        context.fillEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: 12, height: 12))
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: rect.minX + 4, y: rect.minY + 4, width: 4, height: 4))
      case .ink:
        draw(
          points: mark.points.map { localPoint(for: CGPoint(x: $0.x, y: $0.y)) },
          lineWidth: mark.lineWidth, color: NSColor.systemBlue.cgColor, in: context)
      }
    }

    private func drawPreview(in context: CGContext) {
      guard trackingPoints.count > 0 else { return }
      switch tool {
      case .ink:
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        let path = CGMutablePath()
        path.move(to: trackingPoints[0])
        for point in trackingPoints.dropFirst() { path.addLine(to: point) }
        context.addPath(path)
        context.strokePath()
      case .highlight:
        let rect = CGRect(
          x: trackingPoints[0].x,
          y: trackingPoints[0].y,
          width: (trackingPoints.last?.x ?? trackingPoints[0].x) - trackingPoints[0].x,
          height: (trackingPoints.last?.y ?? trackingPoints[0].y) - trackingPoints[0].y
        ).standardized
        context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.22).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.systemYellow.cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
      case .crop:
        let rect = CGRect(
          x: trackingPoints[0].x,
          y: trackingPoints[0].y,
          width: (trackingPoints.last?.x ?? trackingPoints[0].x) - trackingPoints[0].x,
          height: (trackingPoints.last?.y ?? trackingPoints[0].y) - trackingPoints[0].y
        ).standardized
        context.setStrokeColor(NSColor.systemGreen.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 3])
        context.stroke(rect)
      case .mask:
        let rect = CGRect(
          x: trackingPoints[0].x,
          y: trackingPoints[0].y,
          width: (trackingPoints.last?.x ?? trackingPoints[0].x) - trackingPoints[0].x,
          height: (trackingPoints.last?.y ?? trackingPoints[0].y) - trackingPoints[0].y
        ).standardized
        context.setFillColor(NSColor.black.cgColor)
        context.fill(rect)
      case .note, .pointer:
        break
      }
    }

    private func draw(points: [CGPoint], lineWidth: Double, color: CGColor, in context: CGContext) {
      guard let first = points.first else { return }
      let path = CGMutablePath()
      path.move(to: first)
      for point in points.dropFirst() { path.addLine(to: point) }
      context.setStrokeColor(color)
      context.setLineWidth(max(1, CGFloat(lineWidth) * (pdfView?.scaleFactor ?? 1)))
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.addPath(path)
      context.strokePath()
    }

    private func finishGesture() {
      defer {
        tracking = false
        trackingPoints.removeAll()
        needsDisplay = true
      }
      guard !trackingPoints.isEmpty else { return }
      let pagePoints = trackingPoints.compactMap(pagePoint(for:))
      guard !pagePoints.isEmpty else { return }
      switch tool {
      case .highlight:
        onGesture(.highlight(pagePoints), page)
      case .note:
        onGesture(.note(pagePoints[0]), page)
      case .ink:
        onGesture(
          .ink(
            points: pagePoints,
            drawingData: nil,
            pencilContentVersion: nil,
            pencilCanvasTransform: nil
          ),
          page
        )
      case .crop:
        onGesture(.crop(pagePoints), page)
      case .mask:
        onGesture(.mask(pagePoints), page)
      case .pointer:
        break
      }
    }

    private func pagePoint(for point: CGPoint) -> CGPoint? {
      guard let pdfView else { return nil }
      let viewPoint = convert(point, to: pdfView)
      return pdfView.convert(viewPoint, to: page)
    }

    private func localPoint(for pagePoint: CGPoint) -> CGPoint {
      guard let pdfView else { return .zero }
      let viewPoint = pdfView.convert(pagePoint, from: page)
      return convert(viewPoint, from: pdfView)
    }

    private func localRect(for pageRect: CGRect) -> CGRect {
      CGRect(
        x: localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY)).x,
        y: localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY)).y,
        width: localPoint(for: CGPoint(x: pageRect.maxX, y: pageRect.maxY)).x
          - localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY)).x,
        height: localPoint(for: CGPoint(x: pageRect.maxX, y: pageRect.maxY)).y
          - localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY)).y
      ).standardized
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
      hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
  }
#endif

#if os(iOS)
  private struct LiveIOSPDFView: UIViewRepresentable {
    let input: DocumentInput
    let marks: [DocumentMark]
    let masked: Bool
    let readOnly: Bool
    let focusedRegion: PageRegion?
    @Binding var pageIndex: Int
    @Binding var zoom: Double
    let tool: LiveDocumentTool
    let onGesture: LiveDocumentGestureHandler

    func makeCoordinator() -> Coordinator {
      .init()
    }

    func makeUIView(context: Context) -> PDFView {
      let view = PDFView(frame: .zero)
      view.displayMode = .singlePageContinuous
      view.displayDirection = .vertical
      view.displayBox = .cropBox
      view.displaysPageBreaks = true
      view.pageBreakMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
      view.backgroundColor = .systemGroupedBackground
      view.autoScales = false
      view.minScaleFactor = 0.4
      view.maxScaleFactor = 4
      context.coordinator.attach(
        view,
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        focusedRegion: focusedRegion,
        pageIndex: pageIndex,
        zoom: zoom,
        tool: tool,
        onGesture: onGesture,
        setPageIndex: { pageIndex = $0 },
        setZoom: { zoom = $0 }
      )
      return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
      context.coordinator.update(
        view,
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        focusedRegion: focusedRegion,
        pageIndex: pageIndex,
        zoom: zoom,
        tool: tool,
        onGesture: onGesture,
        setPageIndex: { pageIndex = $0 },
        setZoom: { zoom = $0 }
      )
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
      coordinator.detach(view)
    }

    @MainActor
    final class Coordinator: NSObject {
      private var document: PDFDocument?
      private var inputSignature: LiveDocumentInputSignature?
      private var lastFocusedRegion: PageRegion?
      private var provider: LiveIOSPageOverlayProvider?
      private var observers: [NSObjectProtocol] = []
      private weak var view: PDFView?
      private var setPageIndex: LivePageIndexHandler?
      private var setZoom: LiveZoomHandler?

      func attach(
        _ view: PDFView,
        input: DocumentInput,
        marks: [DocumentMark],
        masked: Bool,
        readOnly: Bool,
        focusedRegion: PageRegion?,
        pageIndex: Int,
        zoom: Double,
        tool: LiveDocumentTool,
        onGesture: @escaping LiveDocumentGestureHandler,
        setPageIndex: @escaping LivePageIndexHandler,
        setZoom: @escaping LiveZoomHandler
      ) {
        self.view = view
        self.setPageIndex = setPageIndex
        self.setZoom = setZoom
        installObservers(on: view)
        update(
          view,
          input: input,
          marks: marks,
          masked: masked,
          readOnly: readOnly,
          focusedRegion: focusedRegion,
          pageIndex: pageIndex,
          zoom: zoom,
          tool: tool,
          onGesture: onGesture,
          setPageIndex: setPageIndex,
          setZoom: setZoom
        )
      }

      func update(
        _ view: PDFView,
        input: DocumentInput,
        marks: [DocumentMark],
        masked: Bool,
        readOnly: Bool,
        focusedRegion: PageRegion?,
        pageIndex: Int,
        zoom: Double,
        tool: LiveDocumentTool,
        onGesture: @escaping LiveDocumentGestureHandler,
        setPageIndex: @escaping LivePageIndexHandler,
        setZoom: @escaping LiveZoomHandler
      ) {
        self.view = view
        self.setPageIndex = setPageIndex
        self.setZoom = setZoom
        let signature = LiveDocumentInputSignature(input: input)
        if inputSignature != signature {
          provider?.flushAll()
          view.pageOverlayViewProvider = nil
          view.document = nil
          document = nil
          view.isInMarkupMode = true
          let loadedDocument = LivePDFDocumentLoader.load(input: input)
          let nextProvider = LiveIOSPageOverlayProvider(
            input: input,
            marks: marks,
            masked: masked,
            readOnly: readOnly,
            tool: tool,
            onGesture: onGesture
          )
          provider = nextProvider
          view.pageOverlayViewProvider = nextProvider
          document = loadedDocument
          view.document = loadedDocument
          inputSignature = signature
        } else {
          provider?.update(
            input: input,
            marks: marks,
            masked: masked,
            readOnly: readOnly,
            tool: tool,
            onGesture: onGesture
          )
        }
        view.isInMarkupMode = true
        guard let document, document.pageCount > 0 else { return }
        let boundedPage = min(max(0, pageIndex), document.pageCount - 1)
        if let currentPage = view.currentPage,
          document.index(for: currentPage) != boundedPage,
          let destinationPage = document.page(at: boundedPage)
        {
          view.go(to: destinationPage)
        } else if view.currentPage == nil, let destinationPage = document.page(at: boundedPage) {
          view.go(to: destinationPage)
        }
        let boundedZoom = min(max(0.4, zoom), 4)
        if abs(view.scaleFactor - boundedZoom) > 0.001 {
          view.scaleFactor = boundedZoom
        }
        focus(
          focusedRegion,
          input: input,
          document: document,
          in: view
        )
      }

      func detach(_ view: PDFView) {
        provider?.flushAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        view.pageOverlayViewProvider = nil
        view.document = nil
        provider = nil
        document = nil
        lastFocusedRegion = nil
        self.view = nil
        setPageIndex = nil
        setZoom = nil
      }

      private func installObservers(on view: PDFView) {
        let center = NotificationCenter.default
        observers.append(
          center.addObserver(
            forName: .PDFViewPageChanged,
            object: view,
            queue: .main
          ) { [weak self] _ in
            Task { @MainActor [weak self] in
              self?.provider?.flushAll()
              guard let view = self?.view,
                let page = view.currentPage,
                let document = view.document
              else {
                return
              }
              self?.setPageIndex?(document.index(for: page))
            }
          })
        observers.append(
          center.addObserver(
            forName: .PDFViewScaleChanged,
            object: view,
            queue: .main
          ) { [weak self] _ in
            Task { @MainActor [weak self] in
              guard let view = self?.view else { return }
              self?.provider?.refreshAll()
              self?.setZoom?(Double(view.scaleFactor))
            }
          })
      }

      private func focus(
        _ region: PageRegion?,
        input: DocumentInput,
        document: PDFDocument,
        in view: PDFView
      ) {
        guard region != lastFocusedRegion,
          let region,
          let pageRecord = input.record.pages.first(where: { $0.id == region.pageID }),
          let page = document.page(at: pageRecord.index),
          (try? DocumentGeometry.validate(region, input: input)) != nil
        else { return }
        view.go(to: region.bounds.cgRect, on: page)
        lastFocusedRegion = region
      }
    }
  }

  @MainActor
  private final class LiveIOSPageOverlayProvider: NSObject,
    @preconcurrency PDFPageOverlayViewProvider
  {
    private var input: DocumentInput
    private var marks: [DocumentMark]
    private var masked: Bool
    private var readOnly: Bool
    private var tool: LiveDocumentTool
    private var onGesture: LiveDocumentGestureHandler
    private weak var pdfView: PDFView?
    private var overlays: [ObjectIdentifier: LiveIOSPageOverlayView] = [:]

    init(
      input: DocumentInput,
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.input = input
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
    }

    func update(
      input: DocumentInput,
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.input = input
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
      for overlay in overlays.values {
        overlay.update(
          marks: marks,
          masked: masked,
          readOnly: readOnly,
          tool: tool,
          onGesture: onGesture
        )
      }
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
      pdfView = view
      let key = ObjectIdentifier(page)
      if let overlay = overlays[key] { return overlay }
      let overlay = LiveIOSPageOverlayView(
        frame: .zero,
        pdfView: view,
        page: page,
        input: input,
        marks: marks,
        masked: masked,
        readOnly: readOnly,
        tool: tool,
        onGesture: onGesture
      )
      overlays[key] = overlay
      return overlay
    }

    func pdfView(
      _ pdfView: PDFView,
      willEndDisplayingOverlayView overlayView: UIView,
      for page: PDFPage
    ) {
      (overlayView as? LiveIOSPageOverlayView)?.flush()
      overlays.removeValue(forKey: ObjectIdentifier(page))
    }

    func flushAll() {
      for overlay in overlays.values {
        overlay.flush()
      }
    }

    func refreshAll() {
      for overlay in overlays.values {
        overlay.refreshLayoutAndDisplay()
      }
    }
  }

  @MainActor
  private final class LiveIOSPageOverlayView: UIView, @preconcurrency PKCanvasViewDelegate {
    private weak var pdfView: PDFView?
    private let page: PDFPage
    private let input: DocumentInput
    private var marks: [DocumentMark]
    private var masked: Bool
    private var readOnly: Bool
    private var tool: LiveDocumentTool
    private var onGesture: LiveDocumentGestureHandler
    private let canvasView: PKCanvasView
    private let annotationView: LiveIOSAnnotationSurface
    private var trackingPoints: [CGPoint] = []
    private var tracking = false
    private var baselineStrokeCount = 0
    private var scheduledFlush = false
    private var drawingInProgress = false
    private var lastLayoutSize: CGSize = .zero

    init(
      frame frameRect: CGRect,
      pdfView: PDFView,
      page: PDFPage,
      input: DocumentInput,
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.pdfView = pdfView
      self.page = page
      self.input = input
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
      self.canvasView = PKCanvasView(frame: .zero)
      self.annotationView = LiveIOSAnnotationSurface(frame: .zero, input: input)
      super.init(frame: frameRect)
      backgroundColor = .clear
      isOpaque = false
      clipsToBounds = false

      canvasView.backgroundColor = .clear
      canvasView.isOpaque = false
      canvasView.isScrollEnabled = false
      canvasView.alwaysBounceVertical = false
      canvasView.alwaysBounceHorizontal = false
      canvasView.drawingPolicy = .anyInput
      canvasView.delegate = self
      canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(canvasView)

      annotationView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      annotationView.pdfView = pdfView
      annotationView.page = page
      annotationView.update(marks: marks, masked: masked, tool: tool)
      addSubview(annotationView)

      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      pan.maximumNumberOfTouches = 1
      addGestureRecognizer(pan)
      let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      addGestureRecognizer(tap)
      updateInteraction()
      reloadDrawing()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func update(
      marks: [DocumentMark],
      masked: Bool,
      readOnly: Bool,
      tool: LiveDocumentTool,
      onGesture: @escaping LiveDocumentGestureHandler
    ) {
      self.marks = marks
      self.masked = masked
      self.readOnly = readOnly
      self.tool = tool
      self.onGesture = onGesture
      annotationView.update(marks: marks, masked: masked, tool: tool)
      updateInteraction()
      reloadDrawing()
      setNeedsLayout()
      setNeedsDisplay()
    }

    func refreshLayoutAndDisplay() {
      setNeedsLayout()
      annotationView.setNeedsDisplay()
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      canvasView.frame = bounds
      annotationView.frame = bounds
      if lastLayoutSize != bounds.size {
        lastLayoutSize = bounds.size
        reloadDrawing()
      }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      guard !readOnly, tool != .pointer else { return nil }
      return super.hitTest(point, with: event)
    }

    func flush() {
      drawingInProgress = false
      if tool == .ink {
        scheduleDrawingFlush()
      }
      if tracking {
        finishGesture()
      }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
      drawingInProgress = true
      scheduledFlush = false
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
      drawingInProgress = false
      scheduleDrawingFlush()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      if !drawingInProgress { scheduleDrawingFlush() }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard !readOnly, tool == .highlight || tool == .crop || tool == .mask else { return }
      let point = recognizer.location(in: self)
      switch recognizer.state {
      case .began:
        tracking = true
        trackingPoints = [point]
        annotationView.previewPoints = trackingPoints
      case .changed:
        if trackingPoints.last.map({ distance($0, point) > 0.5 }) ?? true {
          trackingPoints.append(point)
          annotationView.previewPoints = trackingPoints
        }
      case .ended, .cancelled, .failed:
        if trackingPoints.last.map({ distance($0, point) > 0.5 }) ?? true {
          trackingPoints.append(point)
        }
        finishGesture()
      default:
        break
      }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard !readOnly, tool == .note, recognizer.state == .ended else { return }
      let point = recognizer.location(in: self)
      guard let pagePoint = pagePoint(for: point) else { return }
      onGesture(.note(pagePoint), page)
    }

    private func updateInteraction() {
      let editing = !readOnly
      canvasView.isUserInteractionEnabled = editing && tool == .ink
      canvasView.drawingGestureRecognizer.isEnabled = editing && tool == .ink
      for recognizer in gestureRecognizers ?? [] {
        if let pan = recognizer as? UIPanGestureRecognizer {
          pan.isEnabled = editing && (tool == .highlight || tool == .crop || tool == .mask)
        }
        if let tap = recognizer as? UITapGestureRecognizer {
          tap.isEnabled = editing && tool == .note
        }
      }
    }

    private func reloadDrawing() {
      let hasPersistedDrawing = visibleMarks.contains { $0.kind == .ink && $0.pencilDrawing != nil }
      guard hasPersistedDrawing || canvasView.drawing.strokes.isEmpty else { return }
      var canonicalDrawing = PKDrawing()
      for mark in visibleMarks where mark.kind == .ink {
        guard let data = mark.pencilDrawing, let drawing = try? PKDrawing(data: data) else {
          continue
        }
        canonicalDrawing = canonicalDrawing.appending(drawing)
      }
      let transformed = canonicalDrawing.transformed(using: pageToOverlayTransform())
      canvasView.drawing = transformed
      baselineStrokeCount = transformed.strokes.count
    }

    private func scheduleDrawingFlush() {
      guard !scheduledFlush else { return }
      scheduledFlush = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.scheduledFlush = false
        self.performDrawingFlush()
      }
    }

    private func performDrawingFlush() {
      guard tool == .ink else { return }
      let strokes = canvasView.drawing.strokes
      guard strokes.count > baselineStrokeCount else { return }
      let newStrokes = Array(strokes.dropFirst(baselineStrokeCount))
      let canvasTransform = overlayToPageTransform()
      let transformCoefficients = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
      for stroke in newStrokes {
        let localDrawing = PKDrawing(strokes: [stroke])
        let canonicalDrawing = localDrawing.transformed(using: canvasTransform)
        let points = (0..<stroke.path.count).map { index in
          let local = stroke.path[index].location.applying(stroke.transform)
          return local.applying(canvasTransform)
        }
        guard !points.isEmpty else { continue }
        onGesture(
          .ink(
            points: points,
            drawingData: canonicalDrawing.dataRepresentation(),
            pencilContentVersion: Int(canonicalDrawing.requiredContentVersion.rawValue),
            pencilCanvasTransform: transformCoefficients
          ),
          page
        )
      }
      baselineStrokeCount = strokes.count
    }

    private func finishGesture() {
      defer {
        tracking = false
        trackingPoints.removeAll()
        annotationView.previewPoints = []
      }
      guard !trackingPoints.isEmpty else { return }
      let points = trackingPoints.compactMap(pagePoint(for:))
      guard !points.isEmpty else { return }
      switch tool {
      case .highlight:
        onGesture(.highlight(points), page)
      case .crop:
        onGesture(.crop(points), page)
      case .mask:
        onGesture(.mask(points), page)
      case .pointer, .note, .ink:
        break
      }
    }

    private var visibleMarks: [DocumentMark] {
      marks.filter { mark in
        guard mark.region.documentID == input.record.id,
          mark.region.documentRevisionID == input.record.revisionID,
          let document = page.document,
          input.record.pages.first(where: { $0.index == document.index(for: page) })?.id
            == mark.region.pageID
        else { return false }
        guard masked || mark.kind != .displayMask else { return false }
        return true
      }
    }

    private func pagePoint(for point: CGPoint) -> CGPoint? {
      guard let pdfView else { return nil }
      let viewPoint = convert(point, to: pdfView)
      return pdfView.convert(viewPoint, to: page)
    }

    private func overlayToPageTransform() -> CGAffineTransform {
      let origin = pagePoint(for: .zero) ?? .zero
      let x = pagePoint(for: CGPoint(x: 1, y: 0)) ?? origin
      let y = pagePoint(for: CGPoint(x: 0, y: 1)) ?? origin
      return CGAffineTransform(
        a: x.x - origin.x,
        b: x.y - origin.y,
        c: y.x - origin.x,
        d: y.y - origin.y,
        tx: origin.x,
        ty: origin.y
      )
    }

    private func pageToOverlayTransform() -> CGAffineTransform {
      overlayToPageTransform().inverted()
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
      hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
  }

  @MainActor
  private final class LiveIOSAnnotationSurface: UIView {
    weak var pdfView: PDFView?
    var page: PDFPage?
    private let input: DocumentInput
    private var marks: [DocumentMark] = []
    private var masked = false
    private var tool: LiveDocumentTool = .pointer
    var previewPoints: [CGPoint] = [] {
      didSet { setNeedsDisplay() }
    }

    override var isUserInteractionEnabled: Bool {
      get { false }
      set {}
    }

    init(frame frameRect: CGRect, input: DocumentInput) {
      self.input = input
      super.init(frame: frameRect)
      backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func update(marks: [DocumentMark], masked: Bool, tool: LiveDocumentTool) {
      self.marks = marks
      self.masked = masked
      self.tool = tool
      setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
      guard let context = UIGraphicsGetCurrentContext(), let page else { return }
      for mark in marks {
        guard mark.region.pageID == pageRecordID(for: page),
          masked || mark.kind != .displayMask,
          mark.kind != .ink || mark.pencilDrawing == nil
        else { continue }
        draw(mark: mark, page: page, in: context)
      }
      guard previewPoints.count > 1 else { return }
      if tool == .mask {
        let previewRect = CGRect(
          x: previewPoints[0].x,
          y: previewPoints[0].y,
          width: (previewPoints.last?.x ?? previewPoints[0].x) - previewPoints[0].x,
          height: (previewPoints.last?.y ?? previewPoints[0].y) - previewPoints[0].y
        ).standardized
        context.setFillColor(UIColor.black.cgColor)
        context.fill(previewRect)
        return
      }
      let preview = UIBezierPath()
      preview.move(to: previewPoints[0])
      for point in previewPoints.dropFirst() { preview.addLine(to: point) }
      context.setStrokeColor(UIColor.systemGreen.cgColor)
      context.setLineWidth(tool == .crop ? 1.5 : 2)
      if tool == .crop { context.setLineDash(phase: 0, lengths: [5, 3]) }
      preview.stroke()
    }

    private func draw(mark: DocumentMark, page: PDFPage, in context: CGContext) {
      let rect = localRect(for: mark.region.bounds.cgRect, page: page)
      switch mark.kind {
      case .displayMask:
        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)
      case .highlight:
        context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.30).cgColor)
        context.fill(rect)
        context.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.75).cgColor)
        context.setLineWidth(1)
        context.stroke(rect)
      case .note:
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fillEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: 12, height: 12))
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: rect.minX + 4, y: rect.minY + 4, width: 4, height: 4))
      case .ink:
        let path = UIBezierPath()
        let points = mark.points.map { localPoint(for: CGPoint(x: $0.x, y: $0.y), page: page) }
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        UIColor.systemBlue.setStroke()
        path.lineWidth = max(1, CGFloat(mark.lineWidth) * (pdfView?.scaleFactor ?? 1))
        path.lineCapStyle = .round
        path.stroke()
      }
    }

    private func pageRecordID(for page: PDFPage) -> UUID? {
      guard let document = page.document else { return nil }
      return input.record.pages.first(where: { $0.index == document.index(for: page) })?.id
    }

    private func localPoint(for pagePoint: CGPoint, page: PDFPage) -> CGPoint {
      guard let pdfView else { return .zero }
      let viewPoint = pdfView.convert(pagePoint, from: page)
      return convert(viewPoint, from: pdfView)
    }

    private func localRect(for pageRect: CGRect, page: PDFPage) -> CGRect {
      CGRect(
        x: localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY), page: page).x,
        y: localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY), page: page).y,
        width: localPoint(for: CGPoint(x: pageRect.maxX, y: pageRect.maxY), page: page).x
          - localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY), page: page).x,
        height: localPoint(for: CGPoint(x: pageRect.maxX, y: pageRect.maxY), page: page).y
          - localPoint(for: CGPoint(x: pageRect.minX, y: pageRect.minY), page: page).y
      ).standardized
    }
  }
#endif

private struct LiveDocumentInputSignature: Equatable {
  let documentID: UUID
  let revisionID: UUID
  let url: URL

  init(input: DocumentInput) {
    documentID = input.record.id
    revisionID = input.record.revisionID
    url = input.url
  }
}

@MainActor
private enum LivePDFDocumentLoader {
  static func load(input: DocumentInput) -> PDFDocument? {
    guard let document = try? DocumentPDFKitBridge.document(for: input), document.pageCount > 0
    else { return nil }
    return document
  }
}
