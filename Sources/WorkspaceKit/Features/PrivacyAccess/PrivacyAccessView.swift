import SwiftUI

@MainActor
public struct PrivacyAccessView: View {
  @Bindable private var accessController: LocalAccessController
  @Binding private var masksEnabled: Bool
  private let onDismiss: () -> Void

  @State private var statusMessage: String?
  @State private var errorMessage: String?
  @Environment(\.scenePhase) private var scenePhase

  public init(
    accessController: LocalAccessController,
    masksEnabled: Binding<Bool>,
    onDismiss: @escaping () -> Void
  ) {
    _accessController = Bindable(accessController)
    _masksEnabled = masksEnabled
    self.onDismiss = onDismiss
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        accessCard
        maskingCard
        privacyNotice
        lifecycleNote
        statusArea
      }
      .frame(maxWidth: 720, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(WorkspaceStyle.background)
    .foregroundStyle(WorkspaceStyle.ink)
    .tint(WorkspaceStyle.accent)
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        accessController.applicationDidEnterBackground()
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "lock.shield")
        .font(.system(size: 27, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.accent)
        .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 5) {
        Text("Privacy and local access")
          .font(.system(size: 23, weight: .semibold))
        Text("Keep review controls clear about what the device can protect.")
          .font(.system(size: 13))
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      Button("Done", action: onDismiss)
        .buttonStyle(.bordered)
        .accessibilityHint("Closes privacy and local access")
    }
  }

  private var accessCard: some View {
    VStack(alignment: .leading, spacing: 15) {
      cardHeading(
        title: "Optional device-owner lock",
        subtitle:
          "Authentication happens on this device. No school account or network sign-in is used.",
        systemImage: accessController.isLocked ? "lock.fill" : "lock.open"
      )

      HStack(alignment: .top, spacing: 10) {
        Image(systemName: lockStateSymbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(lockStateColor)
          .frame(width: 22, height: 22)

        VStack(alignment: .leading, spacing: 3) {
          Text(lockStateTitle)
            .font(.system(size: 13, weight: .semibold))
          Text(lockStateDescription)
            .font(.system(size: 11))
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 6)
        if accessController.isAuthenticating {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Device-owner authentication in progress")
        }
      }
      .padding(12)
      .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 9))

      Toggle(isOn: accessPolicyBinding) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Require device-owner authentication")
            .font(.system(size: 13, weight: .medium))
          Text("The local lock is optional and does not grant institutional grader permissions.")
            .font(.system(size: 11))
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .disabled(accessController.isAuthenticating)
      .accessibilityHint("Uses the device passcode or available biometrics when enabled")

      if accessController.isEnabled {
        HStack {
          if accessController.isLocked {
            Button(action: beginUnlock) {
              Label("Unlock with device owner", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .disabled(accessController.isAuthenticating)
            .accessibilityHint("Unlocks this local workspace after device-owner authentication")
          } else {
            Button {
              accessController.lock()
              statusMessage = "The local workspace is locked."
              errorMessage = nil
            } label: {
              Label("Lock now", systemImage: "lock")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Locks the local workspace immediately")
          }
          Spacer(minLength: 4)
        }
      }
    }
    .workspaceCard()
  }

  private var maskingCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      cardHeading(
        title: "Display masking",
        subtitle: "Choose whether review surfaces use candidate aliases.",
        systemImage: "eye.slash"
      )

      Toggle(isOn: $masksEnabled) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Mask candidate labels in review")
            .font(.system(size: 13, weight: .medium))
          Text(maskingDescription)
            .font(.system(size: 11))
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .accessibilityValue(masksEnabled ? "On" : "Off")
      .accessibilityHint("Changes display labels only and does not alter source documents")

      HStack(alignment: .top, spacing: 9) {
        Image(systemName: "arrow.uturn.backward.circle")
          .foregroundStyle(WorkspaceStyle.accent)
        Text(
          "Masking is reversible display masking. It does not change the original document, identity mapping, or stored files."
        )
        .font(.system(size: 11))
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .workspaceCard()
  }

  private var privacyNotice: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("Masking is not secure redaction", systemImage: "exclamationmark.triangle")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.ink)
      Text(
        "Document pixels, handwriting, filenames, PDF metadata, annotations, and OCR text may still identify a candidate. Use masking to reduce accidental exposure during review; do not describe it as anonymous, redacted, or secure."
      )
      .font(.system(size: 12))
      .foregroundStyle(WorkspaceStyle.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(15)
    .background(WorkspaceStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
    .overlay(
      RoundedRectangle(cornerRadius: 11)
        .stroke(WorkspaceStyle.accent.opacity(0.28), lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Display masking is not secure redaction. Document pixels, handwriting, filenames, PDF metadata, annotations, and OCR text may still identify a candidate."
    )
  }

  private var lifecycleNote: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "person.badge.key")
        .foregroundStyle(WorkspaceStyle.accent)
      Text(
        "The device owner is the only local access identity in this milestone. A local lock does not prove school authorization, and its setting does not travel with a workspace archive."
      )
      .font(.system(size: 11))
      .foregroundStyle(WorkspaceStyle.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 4)
  }

  @ViewBuilder
  private var statusArea: some View {
    if let errorMessage {
      Label(errorMessage, systemImage: "xmark.octagon")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isStaticText)
    } else if let statusMessage {
      Label(statusMessage, systemImage: "checkmark.circle")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WorkspaceStyle.accent)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isStaticText)
    }
  }

  private var accessPolicyBinding: Binding<Bool> {
    Binding(
      get: { accessController.isEnabled },
      set: { enabled in
        Task { @MainActor in
          await changeAccessPolicy(enabled)
        }
      }
    )
  }

  private var lockStateSymbol: String {
    if accessController.isAuthenticating { return "ellipsis.circle" }
    if accessController.isLocked { return "lock.fill" }
    return accessController.isEnabled ? "checkmark.shield.fill" : "lock.open"
  }

  private var lockStateTitle: String {
    if accessController.isAuthenticating { return "Checking device owner…" }
    if accessController.isLocked { return "Workspace locked" }
    return accessController.isEnabled ? "Workspace unlocked" : "Local lock is off"
  }

  private var lockStateDescription: String {
    if accessController.isAuthenticating {
      return "Finish the device prompt to continue."
    }
    if accessController.isLocked {
      return "Review content should remain unavailable until the device owner unlocks it."
    }
    if accessController.isEnabled {
      return "The device owner can view this local workspace until it relocks."
    }
    return "The app relies on the device account and operating-system protections."
  }

  private var lockStateColor: Color {
    if accessController.isLocked { return .orange }
    return accessController.isEnabled ? WorkspaceStyle.accent : WorkspaceStyle.secondary
  }

  private var maskingDescription: String {
    if masksEnabled {
      return
        "Aliases are shown in supported review labels while the original identity remains stored separately."
    }
    return "Known identity labels may be shown to the unlocked local owner."
  }

  private func cardHeading(title: String, subtitle: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(WorkspaceStyle.accent)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private func changeAccessPolicy(_ enabled: Bool) async {
    statusMessage = nil
    errorMessage = nil
    do {
      try await accessController.setEnabled(enabled)
      statusMessage =
        enabled
        ? "The optional local lock is enabled."
        : "The optional local lock is disabled."
    } catch {
      errorMessage = accessErrorMessage(for: error)
    }
  }

  private func beginUnlock() {
    statusMessage = nil
    errorMessage = nil
    Task { @MainActor in
      do {
        try await accessController.unlock(reason: "Unlock the local grading workspace")
        statusMessage = "The local workspace is unlocked on this device."
      } catch {
        errorMessage = accessErrorMessage(for: error)
      }
    }
  }

  private func accessErrorMessage(for error: Error) -> String {
    if let failure = error as? LocalAccessFailure, let description = failure.errorDescription {
      return description
    }
    return "The workspace remained locked because device-owner authentication did not succeed."
  }
}
