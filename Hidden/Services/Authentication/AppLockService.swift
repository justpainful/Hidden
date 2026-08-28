import Foundation
import LocalAuthentication
import Observation

/// When the app relocks after leaving the foreground.
enum LockTimeout: String, CaseIterable, Identifiable, Sendable {
    case immediately
    case after30Seconds
    case after1Minute
    case after5Minutes

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .immediately:   return 0
        case .after30Seconds: return 30
        case .after1Minute:  return 60
        case .after5Minutes: return 300
        }
    }

    var title: String {
        switch self {
        case .immediately:    return String(localized: "Immediately")
        case .after30Seconds: return String(localized: "After 30 Seconds")
        case .after1Minute:   return String(localized: "After 1 Minute")
        case .after5Minutes:  return String(localized: "After 5 Minutes")
        }
    }
}

/// The app's own lock. Face ID with device-passcode fallback, through `LocalAuthentication`.
///
/// This locks *the app*. It has no relationship to Apple's protection of the system Hidden
/// album, which no third-party app can authenticate for — the UI never claims otherwise.
@MainActor
@Observable
final class AppLockService {
    /// Whether the user has turned the app lock on at all.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "appLockEnabled")
            if !isEnabled { isLocked = false }
            if isEnabled && oldValue == false { isLocked = true }
        }
    }

    var timeout: LockTimeout {
        didSet { UserDefaults.standard.set(timeout.rawValue, forKey: "appLockTimeout") }
    }

    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    /// When the app last left the foreground, for the timeout comparison on return.
    private var backgroundedAt: Date?

    init() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "appLockEnabled")
        isEnabled = enabled
        timeout = LockTimeout(rawValue: defaults.string(forKey: "appLockTimeout") ?? "") ?? .immediately
        isLocked = enabled
    }

    /// Whether this device can evaluate any authentication at all.
    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
    }

    @discardableResult
    func unlock(reason: String = String(localized: "Unlock Hidden")) async -> Bool {
        guard isLocked else { return true }
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // A device with no passcode set cannot authenticate at all. Staying locked
            // forever would lock the user out of their own app; the honest behaviour is to
            // open and tell them the lock is not enforceable.
            lastError = error?.localizedDescription
            isLocked = false
            return true
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isLocked = false
                lastError = nil
            }
            return success
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: Scene phase

    func appDidEnterBackground() {
        backgroundedAt = .now
        if isEnabled && timeout == .immediately {
            isLocked = true
        }
    }

    func appWillEnterForeground() {
        guard isEnabled, !isLocked, let backgroundedAt else { return }
        if Date.now.timeIntervalSince(backgroundedAt) >= timeout.seconds {
            isLocked = true
        }
        self.backgroundedAt = nil
    }
}
