import CoreGraphics
import Foundation
import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

public struct LiveOCRPane: View {
  private let blocks: [TranscriptBlock]
  private let inputs: [DocumentInput]
  private let readOnly: Bool
  private let masked: Bool
  private let onBlocksChange: ([TranscriptBlock]) -> Void
  private let onFocus: (PageRegion) -> Void

  @State private var editableBlocks: [TranscriptBlock]
  @State private var correctionDrafts: [UUID: String]
  @State private var pendingCorrectionIDs: Set<UUID> = []
  @State private var submittedCorrectionValues: [UUID: String] = [:]
  @State private var cropDrafts: [UUID: LiveCropRegionDraft]
  @State private var pendingCropIDs: Set<UUID> = []
  @State private var submittedCropRegions: [UUID: PageRegion] = [:]
  @State private var cropMessages: [UUID: String] = [:]

  public init(
    blocks: [TranscriptBlock],
    inputs: [DocumentInput],
    readOnly: Bool,
    masked: Bool,
    onBlocksChange: @escaping ([TranscriptBlock]) -> Void,
    onFocus: @escaping (PageRegion) -> Void
  ) {
    self.blocks = blocks
    self.inputs = inputs
    self.readOnly = readOnly
    self.masked = masked
    self.onBlocksChange = onBlocksChange
    self.onFocus = onFocus
    _editableBlocks = State(initialValue: blocks)
    _correctionDrafts = State(
      initialValue: Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.correction ?? "") })
    )
    _cropDrafts = State(
      initialValue: Dictionary(
        uniqueKeysWithValues:
          blocks
          .filter { $0.kind == .imageCrop }
          .map { ($0.id, LiveCropRegionDraft(region: $0.region)) }
      )
    )
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        header
        sourceSummary
        if editableBlocks.isEmpty {
          emptyState
        } else {
          ForEach(editableBlocks) { block in
            blockCard(block)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(WorkspaceStyle.background)
    .foregroundStyle(WorkspaceStyle.ink)
    .onChange(of: blocks) { _, newBlocks in
      acceptAuthoritativeBlocks(newBlocks)
    }
    .onChange(of: readOnly) { wasReadOnly, isReadOnly in
      if wasReadOnly && !isReadOnly {
        finishPersistenceCycle()
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Source text review")
            .font(.headline)
          Text("Observed text, corrections, and source regions")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 8)
        if masked {
          Label("Display masking", systemImage: "eye.slash")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .accessibilityHint("Masking hides content in this pane but does not change OCR data.")
        }
      }

      if masked {
        Label(
          "Text and image crops are hidden while display masking is enabled.",
          systemImage: "eye.slash.fill"
        )
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .accessibilityElement(children: .combine)
      } else if editingUnavailable {
        Label(editingUnavailableMessage, systemImage: "lock")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .accessibilityElement(children: .combine)
      }
    }
    .padding(14)
    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkspaceStyle.border, lineWidth: 1))
  }

  @ViewBuilder
  private var sourceSummary: some View {
    if inputs.isEmpty {
      Label(
        "No source documents are attached to these OCR blocks.", systemImage: "doc.badge.ellipsis"
      )
      .font(.caption)
      .foregroundStyle(WorkspaceStyle.secondary)
    } else {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "folder")
          .foregroundStyle(WorkspaceStyle.accent)
        VStack(alignment: .leading, spacing: 3) {
          Text("Sources")
            .font(.caption.weight(.semibold))
          Text(
            masked ? maskedSourceSummary : inputs.map(\.record.originalName).joined(separator: ", ")
          )
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .lineLimit(2)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 9))
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No OCR blocks", systemImage: "text.magnifyingglass")
    } description: {
      Text("OCR blocks will appear here when source text is available for review.")
    }
    .frame(maxWidth: .infinity, minHeight: 220)
    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
  }

  private func blockCard(_ block: TranscriptBlock) -> some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Block \(blockNumber(for: block))")
          .font(.subheadline.weight(.semibold))
        Text(block.kind.title)
          .font(.caption.weight(.medium))
          .foregroundStyle(WorkspaceStyle.accent)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(WorkspaceStyle.accent.opacity(0.12), in: Capsule())
        Spacer(minLength: 4)
        confidenceView(for: block)
        blockActions(for: block)
      }

      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 8) {
          if block.kind == .imageCrop {
            cropPreview(for: block)
            cropRegionEditor(for: block)
          }

          labeledText("Observed", systemImage: "quote.opening") {
            masked
              ? AnyView(maskedText)
              : AnyView(
                Text(block.observedText.isEmpty ? "No observed text" : block.observedText).font(
                  .body))
          }

          labeledText("Current display", systemImage: "text.cursor") {
            if masked {
              AnyView(maskedText)
            } else {
              AnyView(
                Text(block.displayText.isEmpty ? "No text" : block.displayText)
                  .font(.body)
                  .foregroundStyle(
                    block.correction == nil ? WorkspaceStyle.secondary : WorkspaceStyle.ink)
              )
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .trailing, spacing: 7) {
          Button {
            onFocus(block.region)
          } label: {
            Label("Show source", systemImage: "scope")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(masked)
          .help("Focus the document reader on this source region")

          if block.kind == .text {
            Button {
              convertToImageCrop(block)
            } label: {
              Label("Use source image", systemImage: "viewfinder.rectangular")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(shouldSuggestCrop(block) ? .orange : WorkspaceStyle.accent)
            .disabled(editingUnavailable || masked)
            .help(
              "Replace this text block with an image crop and focus its source region"
            )
          }
        }
      }

      correctionEditor(for: block)
    }
    .padding(14)
    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkspaceStyle.border, lineWidth: 1))
    .accessibilityElement(children: .contain)
  }

  private func blockActions(for block: TranscriptBlock) -> some View {
    HStack(spacing: 2) {
      Button {
        moveBlock(block, by: -1)
      } label: {
        Image(systemName: "chevron.up")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
      .disabled(editingUnavailable || masked || blockIndex(for: block) == 0)
      .accessibilityLabel("Move block up")
      .help("Move this block earlier in the review order")

      Button {
        moveBlock(block, by: 1)
      } label: {
        Image(systemName: "chevron.down")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
      .disabled(
        editingUnavailable || masked || blockIndex(for: block) >= editableBlocks.count - 1
      )
      .accessibilityLabel("Move block down")
      .help("Move this block later in the review order")

      Button(role: .destructive) {
        removeBlock(block)
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
      .disabled(editingUnavailable || masked)
      .accessibilityLabel("Remove block")
      .help("Remove this OCR block from the review")
    }
  }

  @ViewBuilder
  private func cropRegionEditor(for block: TranscriptBlock) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Crop bounds in canonical page points")
        .font(.caption.weight(.semibold))
      Text("x and y use the unrotated page coordinate system.")
        .font(.caption2)
        .foregroundStyle(WorkspaceStyle.secondary)

      LazyVGrid(
        columns: [GridItem(.flexible(minimum: 72)), GridItem(.flexible(minimum: 72))],
        alignment: .leading,
        spacing: 7
      ) {
        cropField("x", for: block, keyPath: \.x)
        cropField("y", for: block, keyPath: \.y)
        cropField("width", for: block, keyPath: \.width)
        cropField("height", for: block, keyPath: \.height)
      }

      HStack(spacing: 8) {
        Button("Apply bounds") {
          applyCropRegion(for: block)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(editingUnavailable || masked)

        if pendingCropIDs.contains(block.id) {
          Text("Saving crop…")
            .font(.caption2)
            .foregroundStyle(WorkspaceStyle.secondary)
        }
      }

      if let message = cropMessages[block.id] {
        Text(message)
          .font(.caption2)
          .foregroundStyle(WorkspaceStyle.secondary)
      }
    }
    .padding(9)
    .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
  }

  private func cropField(
    _ title: String,
    for block: TranscriptBlock,
    keyPath: WritableKeyPath<LiveCropRegionDraft, String>
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(WorkspaceStyle.secondary)
      TextField(title, text: cropBinding(for: block, keyPath: keyPath))
        .textFieldStyle(.roundedBorder)
        .font(.caption.monospacedDigit())
        .accessibilityLabel("Crop \(title) in canonical page points")
    }
  }

  @ViewBuilder
  private func correctionEditor(for block: TranscriptBlock) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("Correction", systemImage: "pencil.line")
          .font(.caption.weight(.semibold))
        Spacer()
        if !masked && !editingUnavailable && !correctionDraft(for: block).isEmpty {
          Button("Clear draft") {
            correctionDrafts[block.id] = ""
            pendingCorrectionIDs.remove(block.id)
            submittedCorrectionValues.removeValue(forKey: block.id)
          }
          .buttonStyle(.borderless)
          .font(.caption)
        }
      }

      if masked {
        maskedText
      } else if editingUnavailable {
        Text(block.correction ?? "No correction entered")
          .font(.body)
          .foregroundStyle(block.correction == nil ? WorkspaceStyle.secondary : WorkspaceStyle.ink)
          .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
          .padding(8)
          .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
      } else {
        TextEditor(text: correctionBinding(for: block))
          .font(.body)
          .frame(minHeight: 54, maxHeight: 120)
          .padding(4)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
          .accessibilityLabel("Correction for block \(blockNumber(for: block))")
        HStack(spacing: 8) {
          Button("Save correction") {
            saveCorrection(for: block)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .tint(WorkspaceStyle.accent)
          .disabled(!correctionHasChanges(for: block))

          if pendingCorrectionIDs.contains(block.id) {
            Text("Saving correction…")
              .font(.caption2)
              .foregroundStyle(WorkspaceStyle.secondary)
          }
        }
      }

      if masked {
        Text("Corrections are preserved and become editable when display masking is turned off.")
          .font(.caption2)
          .foregroundStyle(WorkspaceStyle.secondary)
      } else if !editingUnavailable {
        Text("Save a correction explicitly after reviewing the observed text.")
          .font(.caption2)
          .foregroundStyle(WorkspaceStyle.secondary)
      }
    }
  }

  private var maskedText: some View {
    Text("Hidden by display mask")
      .font(.body)
      .foregroundStyle(WorkspaceStyle.secondary)
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
      .padding(8)
      .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
      .foregroundStyle(.white)
      .accessibilityLabel("Content hidden by display mask")
  }

  @ViewBuilder
  private func labeledText<Content: View>(
    _ title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
    }
  }

  @ViewBuilder
  private func confidenceView(for block: TranscriptBlock) -> some View {
    if let confidence = block.confidence {
      let percentage = Int((min(max(confidence, 0), 1) * 100).rounded())
      Label(
        "Confidence \(percentage)%",
        systemImage: confidence < 0.65 ? "exclamationmark.triangle" : "checkmark.circle"
      )
      .font(.caption)
      .foregroundStyle(confidence < 0.65 ? .orange : WorkspaceStyle.secondary)
      .accessibilityLabel("Confidence \(percentage) percent")
    } else {
      Text("Confidence unavailable")
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
    }
  }

  @ViewBuilder
  private func cropPreview(for block: TranscriptBlock) -> some View {
    if masked {
      HStack {
        Image(systemName: "eye.slash")
        Text("Image crop hidden by display mask")
      }
      .font(.caption)
      .foregroundStyle(.white)
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 72)
      .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
    } else if let image = cropImage(for: block) {
      image
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: 180, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
        .accessibilityLabel("Source image crop")
    } else {
      HStack(alignment: .top, spacing: 7) {
        Image(systemName: "photo.badge.exclamationmark")
        Text(
          block.cropAsset == nil
            ? "Source-linked image crop unavailable."
            : "Crop asset and source-linked fallback unavailable."
        )
        .font(.caption)
      }
      .foregroundStyle(WorkspaceStyle.secondary)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private var editingUnavailable: Bool {
    readOnly || isPhone
  }

  private var editingUnavailableMessage: String {
    if readOnly { return "Review-only mode: corrections cannot be changed." }
    return "iPhone review mode: corrections are available on a larger device."
  }

  private var maskedSourceSummary: String {
    let count = inputs.count
    return count == 1
      ? "One source document hidden by display mask."
      : "\(count) source documents hidden by display mask."
  }

  private var isPhone: Bool {
    #if os(iOS)
      return UIDevice.current.userInterfaceIdiom == .phone
    #else
      return false
    #endif
  }

  private func blockNumber(for block: TranscriptBlock) -> Int {
    (editableBlocks.firstIndex(where: { $0.id == block.id }) ?? 0) + 1
  }

  private func blockIndex(for block: TranscriptBlock) -> Int {
    editableBlocks.firstIndex(where: { $0.id == block.id }) ?? -1
  }

  private func shouldSuggestCrop(_ block: TranscriptBlock) -> Bool {
    guard block.kind == .text else { return false }
    if let confidence = block.confidence, confidence < 0.65 { return true }
    let characters = block.observedText.filter { !$0.isWhitespace }
    guard characters.count >= 4 else { return false }
    let symbolCount = characters.filter { !$0.isLetter && !$0.isNumber }.count
    return symbolCount * 2 >= characters.count
  }

  private func correctionBinding(for block: TranscriptBlock) -> Binding<String> {
    Binding(
      get: { correctionDraft(for: block) },
      set: {
        correctionDrafts[block.id] = $0
        pendingCorrectionIDs.remove(block.id)
        submittedCorrectionValues.removeValue(forKey: block.id)
      }
    )
  }

  private func correctionDraft(for block: TranscriptBlock) -> String {
    correctionDrafts[block.id] ?? block.correction ?? ""
  }

  private func correctionHasChanges(for block: TranscriptBlock) -> Bool {
    normalizedCorrection(correctionDraft(for: block)) != block.correction
  }

  private func saveCorrection(for block: TranscriptBlock) {
    guard !editingUnavailable, !masked,
      let index = editableBlocks.firstIndex(where: { $0.id == block.id })
    else { return }
    let value = normalizedCorrection(correctionDraft(for: block))
    guard value != editableBlocks[index].correction else { return }
    var updated = editableBlocks
    updated[index].correction = value
    editableBlocks = updated
    correctionDrafts[block.id] = value ?? ""
    pendingCorrectionIDs.insert(block.id)
    submittedCorrectionValues[block.id] = value ?? ""
    onBlocksChange(updated)
  }

  private func normalizedCorrection(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func acceptAuthoritativeBlocks(_ newBlocks: [TranscriptBlock]) {
    let previousBlocks = Dictionary(uniqueKeysWithValues: editableBlocks.map { ($0.id, $0) })
    let ids = Set(newBlocks.map(\.id))
    var nextCorrectionDrafts = correctionDrafts
    var nextPendingCorrections = pendingCorrectionIDs
    var nextSubmittedCorrections = submittedCorrectionValues
    var nextCropDrafts = cropDrafts
    var nextPendingCrops = pendingCropIDs
    var nextSubmittedCrops = submittedCropRegions
    var nextCropMessages = cropMessages

    for block in newBlocks {
      let previousBlock = previousBlocks[block.id]
      let correctionDraftWasDirty =
        previousBlock.map {
          normalizedCorrection(nextCorrectionDrafts[block.id] ?? $0.correction ?? "")
            != $0.correction
        } ?? false
      if nextPendingCorrections.contains(block.id) {
        if nextSubmittedCorrections[block.id] == (block.correction ?? "") {
          nextPendingCorrections.remove(block.id)
          nextSubmittedCorrections.removeValue(forKey: block.id)
          nextCorrectionDrafts[block.id] = block.correction ?? ""
        }
      } else if !correctionDraftWasDirty {
        nextCorrectionDrafts[block.id] = block.correction ?? ""
      }

      if block.kind == .imageCrop {
        let cropDraftWasDirty =
          previousBlock.map {
            nextCropDrafts[block.id] != LiveCropRegionDraft(region: $0.region)
          } ?? false
        if nextPendingCrops.contains(block.id), nextSubmittedCrops[block.id] == block.region {
          nextPendingCrops.remove(block.id)
          nextSubmittedCrops.removeValue(forKey: block.id)
          nextCropMessages.removeValue(forKey: block.id)
        } else if !nextPendingCrops.contains(block.id) && !cropDraftWasDirty {
          nextCropDrafts[block.id] = LiveCropRegionDraft(region: block.region)
        }
      } else {
        nextCropDrafts.removeValue(forKey: block.id)
        nextPendingCrops.remove(block.id)
        nextSubmittedCrops.removeValue(forKey: block.id)
        nextCropMessages.removeValue(forKey: block.id)
      }
    }

    correctionDrafts = nextCorrectionDrafts.filter { ids.contains($0.key) }
    pendingCorrectionIDs = nextPendingCorrections.intersection(ids)
    submittedCorrectionValues = nextSubmittedCorrections.filter { ids.contains($0.key) }
    cropDrafts = nextCropDrafts.filter { ids.contains($0.key) }
    pendingCropIDs = nextPendingCrops.intersection(ids)
    submittedCropRegions = nextSubmittedCrops.filter { ids.contains($0.key) }
    cropMessages = nextCropMessages.filter { ids.contains($0.key) }
    editableBlocks = newBlocks
  }

  private func finishPersistenceCycle() {
    guard !pendingCorrectionIDs.isEmpty || !pendingCropIDs.isEmpty else { return }
    editableBlocks = blocks
    pendingCorrectionIDs.removeAll()
    submittedCorrectionValues.removeAll()
    for id in pendingCropIDs {
      cropMessages.removeValue(forKey: id)
    }
    pendingCropIDs.removeAll()
    submittedCropRegions.removeAll()
  }

  private func moveBlock(_ block: TranscriptBlock, by offset: Int) {
    guard !editingUnavailable, !masked,
      let index = editableBlocks.firstIndex(where: { $0.id == block.id })
    else { return }
    let destination = index + offset
    guard editableBlocks.indices.contains(destination) else { return }
    var updated = editableBlocks
    updated.swapAt(index, destination)
    editableBlocks = updated
    onBlocksChange(updated)
  }

  private func removeBlock(_ block: TranscriptBlock) {
    guard !editingUnavailable, !masked,
      let index = editableBlocks.firstIndex(where: { $0.id == block.id })
    else { return }
    var updated = editableBlocks
    updated.remove(at: index)
    editableBlocks = updated
    correctionDrafts.removeValue(forKey: block.id)
    pendingCorrectionIDs.remove(block.id)
    submittedCorrectionValues.removeValue(forKey: block.id)
    cropDrafts.removeValue(forKey: block.id)
    pendingCropIDs.remove(block.id)
    submittedCropRegions.removeValue(forKey: block.id)
    cropMessages.removeValue(forKey: block.id)
    onBlocksChange(updated)
  }

  private func cropBinding(
    for block: TranscriptBlock,
    keyPath: WritableKeyPath<LiveCropRegionDraft, String>
  ) -> Binding<String> {
    Binding(
      get: {
        let draft = cropDrafts[block.id] ?? LiveCropRegionDraft(region: block.region)
        return draft[keyPath: keyPath]
      },
      set: { value in
        var draft = cropDrafts[block.id] ?? LiveCropRegionDraft(region: block.region)
        draft[keyPath: keyPath] = value
        cropDrafts[block.id] = draft
        cropMessages[block.id] = nil
        pendingCropIDs.remove(block.id)
        submittedCropRegions.removeValue(forKey: block.id)
      }
    )
  }

  private func applyCropRegion(for block: TranscriptBlock) {
    guard !editingUnavailable, !masked,
      let input = sourceInput(for: block.region),
      let index = editableBlocks.firstIndex(where: { $0.id == block.id })
    else {
      cropMessages[block.id] = "The source document for this crop is unavailable."
      return
    }
    let draft = cropDrafts[block.id] ?? LiveCropRegionDraft(region: block.region)
    guard let x = finiteDouble(draft.x), let y = finiteDouble(draft.y),
      let width = finiteDouble(draft.width), let height = finiteDouble(draft.height)
    else {
      cropMessages[block.id] = "Enter finite numeric bounds."
      return
    }
    let region = PageRegion(
      documentID: input.record.id,
      documentRevisionID: input.record.revisionID,
      pageID: block.region.pageID,
      bounds: PageRectangle(x: x, y: y, width: width, height: height)
    )
    guard (try? DocumentGeometry.validate(region, input: input)) != nil else {
      cropMessages[block.id] = "Bounds must be positive and inside the page crop box."
      return
    }

    var updated = editableBlocks
    updated[index].region = region
    editableBlocks = updated
    cropDrafts[block.id] = LiveCropRegionDraft(region: region)
    pendingCropIDs.insert(block.id)
    submittedCropRegions[block.id] = region
    cropMessages[block.id] = nil
    onBlocksChange(updated)
  }

  private func finiteDouble(_ value: String) -> Double? {
    guard let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
      number.isFinite
    else { return nil }
    return number
  }

  private func convertToImageCrop(_ block: TranscriptBlock) {
    guard !editingUnavailable, !masked,
      let index = editableBlocks.firstIndex(where: { $0.id == block.id })
    else { return }
    var updated = editableBlocks
    let converted = DocumentOCR.imageCropBlock(from: updated[index])
    updated[index] = converted
    editableBlocks = updated
    onBlocksChange(updated)
    onFocus(converted.region)
  }

  private func cropImage(for block: TranscriptBlock) -> Image? {
    if let url = cropURL(for: block), let image = loadImage(from: url) {
      return image
    }
    guard let input = sourceInput(for: block.region),
      let cgImage = try? DocumentRenderer.image(for: block.region, input: input)
    else { return nil }
    return loadImage(from: cgImage)
  }

  private func sourceInput(for region: PageRegion) -> DocumentInput? {
    inputs.first {
      $0.record.id == region.documentID && $0.record.revisionID == region.documentRevisionID
    }
  }

  private func cropURL(for block: TranscriptBlock) -> URL? {
    guard let asset = block.cropAsset, let input = sourceInput(for: block.region) else {
      return nil
    }
    let candidate = input.url.deletingLastPathComponent().appendingPathComponent(asset.relativePath)
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
  }

  private func loadImage(from url: URL) -> Image? {
    #if os(macOS)
      if let image = NSImage(contentsOf: url) {
        return Image(nsImage: image)
      }
      return nil
    #elseif os(iOS)
      if let image = UIImage(contentsOfFile: url.path) {
        return Image(uiImage: image)
      }
      return nil
    #else
      return nil
    #endif
  }

  private func loadImage(from cgImage: CGImage) -> Image? {
    #if os(macOS)
      let size = NSSize(width: cgImage.width, height: cgImage.height)
      return Image(nsImage: NSImage(cgImage: cgImage, size: size))
    #elseif os(iOS)
      return Image(uiImage: UIImage(cgImage: cgImage))
    #else
      return nil
    #endif
  }
}

private struct LiveCropRegionDraft: Equatable {
  var x: String
  var y: String
  var width: String
  var height: String

  init(region: PageRegion) {
    x = Self.format(region.bounds.x)
    y = Self.format(region.bounds.y)
    width = Self.format(region.bounds.width)
    height = Self.format(region.bounds.height)
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.2f", value)
  }
}

extension TranscriptBlockKind {
  fileprivate var title: String {
    switch self {
    case .text: return "Text"
    case .imageCrop: return "Image crop"
    }
  }
}
