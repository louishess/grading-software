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
      editableBlocks = newBlocks
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

      HStack(spacing: 8) {
        Button {
          // Recognition is intentionally owned by the workspace coordinator.
        } label: {
          Label("Run recognition", systemImage: "text.viewfinder")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(true)
        .help("Recognition is started by the workspace coordinator.")

        Button {
          // There is no in-pane recognition task to cancel.
        } label: {
          Label("Cancel", systemImage: "xmark")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(true)
        .help("No recognition task is owned by this view.")

        Text("Language and engine settings are controlled by the workspace coordinator.")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .lineLimit(2)
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
      Text("Run recognition from the workspace coordinator, then review each source region here.")
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
      }

      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 8) {
          if block.kind == .imageCrop {
            cropPreview(for: block)
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
          .help("Focus the document reader on this source region")

          if shouldSuggestCrop(block) {
            Button {
              onFocus(block.region)
            } label: {
              Label("Review crop region", systemImage: "viewfinder.rectangular")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)
            .help(
              "Focus this low-confidence region so a person can explicitly choose a crop in the reader"
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

  @ViewBuilder
  private func correctionEditor(for block: TranscriptBlock) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("Correction", systemImage: "pencil.line")
          .font(.caption.weight(.semibold))
        Spacer()
        if block.correction != nil && !editingUnavailable {
          Button("Clear") {
            updateCorrection(for: block.id, value: nil)
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
      }

      if masked {
        Text("Corrections are preserved and become editable when display masking is turned off.")
          .font(.caption2)
          .foregroundStyle(WorkspaceStyle.secondary)
      } else if !editingUnavailable {
        Text("Edits are emitted to the workspace as review corrections.")
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
    } else if let url = cropURL(for: block), let image = loadImage(from: url) {
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
            ? "No image crop asset recorded." : "Crop asset unavailable at its recorded path."
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
      get: { editableBlocks.first(where: { $0.id == block.id })?.correction ?? "" },
      set: { updateCorrection(for: block.id, value: $0.isEmpty ? nil : $0) }
    )
  }

  private func updateCorrection(for id: UUID, value: String?) {
    guard let index = editableBlocks.firstIndex(where: { $0.id == id }) else { return }
    var updated = editableBlocks
    updated[index].correction = value
    editableBlocks = updated
    onBlocksChange(updated)
  }

  private func cropURL(for block: TranscriptBlock) -> URL? {
    guard let asset = block.cropAsset else { return nil }
    for input in inputs {
      let candidate = input.url.deletingLastPathComponent().appendingPathComponent(
        asset.relativePath)
      if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    return nil
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
}

extension TranscriptBlockKind {
  fileprivate var title: String {
    switch self {
    case .text: return "Text"
    case .imageCrop: return "Image crop"
    }
  }
}
