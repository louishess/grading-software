import Foundation
import LocalAuthentication
import Observation

public protocol DeviceOwnerAuthenticating: Sendable {
  func isAvailable() async -> Bool
  func authenticate(reason: String) async throws -> Bool
}

public protocol LocalAccessPreferenceStoring: Sendable {
  func lockIsEnabled() -> Bool
  func setLockEnabled(_ enabled: Bool)
}

public struct UserDefaultsLocalAccessPreferences: LocalAccessPreferenceStoring, @unchecked Sendable
{
  private let defaults: UserDefaults
  private let key: String

  public init(
    defaults: UserDefaults = .standard,
    key: String = "gradingWorkspace.localDeviceOwnerLockEnabled"
  ) {
    self.defaults = defaults
    self.key = key
  }

  public func lockIsEnabled() -> Bool { defaults.bool(forKey: key) }

  public func setLockEnabled(_ enabled: Bool) { defaults.set(enabled, forKey: key) }
}

public struct SystemDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
  public init() {}

  public func isAvailable() async -> Bool {
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
  }

  public func authenticate(reason: String) async throws -> Bool {
    let context = LAContext()
    context.localizedFallbackTitle = "Use Device Password"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      throw LocalAccessFailure.unavailable
    }
    return try await withCheckedThrowingContinuation { continuation in
      context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
        success, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: success)
        }
      }
    }
  }
}

public enum LocalAccessFailure: Error, LocalizedError, Sendable {
  case unavailable
  case denied

  public var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Device-owner authentication is unavailable on this device."
    case .denied:
      return "The workspace remained locked because authentication did not succeed."
    }
  }
}

@MainActor @Observable
public final class LocalAccessController {
  public private(set) var isEnabled: Bool
  public private(set) var isLocked: Bool
  public private(set) var isAuthenticating = false
  public let inactivityDuration: Duration

  @ObservationIgnored private let authenticator: any DeviceOwnerAuthenticating
  @ObservationIgnored private let preferences: any LocalAccessPreferenceStoring
  @ObservationIgnored private var relockTask: Task<Void, Never>?
  @ObservationIgnored private var authenticationGeneration: UInt64 = 0

  public init(
    authenticator: any DeviceOwnerAuthenticating = SystemDeviceOwnerAuthenticator(),
    preferences: any LocalAccessPreferenceStoring = UserDefaultsLocalAccessPreferences(),
    inactivityDuration: Duration = .seconds(300)
  ) {
    self.authenticator = authenticator
    self.preferences = preferences
    self.inactivityDuration = inactivityDuration
    let restoredEnabled = preferences.lockIsEnabled()
    isEnabled = restoredEnabled
    isLocked = restoredEnabled
  }

  deinit { relockTask?.cancel() }

  public func authenticationIsAvailable() async -> Bool {
    await authenticator.isAvailable()
  }

  public func setEnabled(_ enabled: Bool) async throws {
    guard enabled != isEnabled else {
      if enabled { noteActivity() }
      return
    }
    if enabled {
      guard await authenticator.isAvailable() else { throw LocalAccessFailure.unavailable }
      try await authenticate(reason: "Turn on the local workspace lock")
      isEnabled = true
      isLocked = false
      preferences.setLockEnabled(true)
      noteActivity()
    } else {
      if isLocked {
        try await authenticate(reason: "Turn off the local workspace lock")
      }
      relockTask?.cancel()
      isEnabled = false
      isLocked = false
      preferences.setLockEnabled(false)
    }
  }

  public func unlock(reason: String = "Unlock the local grading workspace") async throws {
    guard isEnabled else {
      isLocked = false
      return
    }
    try await authenticate(reason: reason)
    isLocked = false
    noteActivity()
  }

  public func lock() {
    guard isEnabled else { return }
    authenticationGeneration &+= 1
    relockTask?.cancel()
    isLocked = true
  }

  public func noteActivity() {
    guard isEnabled, !isLocked else { return }
    relockTask?.cancel()
    let duration = inactivityDuration
    relockTask = Task { [weak self] in
      do {
        try await Task.sleep(for: duration)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self?.lock()
    }
  }

  public func applicationDidEnterBackground() {
    authenticationGeneration &+= 1
    if isEnabled {
      relockTask?.cancel()
      isLocked = true
    }
  }

  private func authenticate(reason: String) async throws {
    guard !isAuthenticating else { throw LocalAccessFailure.denied }
    let generation = authenticationGeneration
    isAuthenticating = true
    defer { isAuthenticating = false }
    do {
      guard try await authenticator.authenticate(reason: reason) else {
        throw LocalAccessFailure.denied
      }
      guard authenticationGeneration == generation else { throw LocalAccessFailure.denied }
    } catch is LocalAccessFailure {
      throw LocalAccessFailure.denied
    } catch {
      throw error
    }
  }
}
