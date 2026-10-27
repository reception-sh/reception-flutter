import Foundation
import Observation

/// Implements the Pigeon host API for one Flutter engine. The SDK is a process-wide singleton, so only the most
/// recently connected engine receives state, events and callbacks; `connect()` replaces any earlier connection,
/// including the same engine's after a hot restart.
@MainActor
internal final class ReceptionHost: ReceptionHostApi {
  private static weak var current: ReceptionHost?
  private static var revision: Int64 = 0
  /// The appearance JSON last accepted from Dart, returned in snapshots.
  static var appearanceValues: [String: Any] = [:]
  private let flutterApi: ReceptionFlutterApi
  private let requests = PaywallRequests()
  private var connected = false
  private var settingRevisions: [String: Int64] = [:]
  private var observation = UUID()

  init(flutterApi: ReceptionFlutterApi) {
    self.flutterApi = flutterApi
  }

  func invalidate() {
    connected = false
    observation = UUID()
    requests.cancelAll()
    guard Self.current === self else { return }
    Reception.shared.onEvent = nil
    Reception.shared.onPaywall = nil
    // A missing Dart callback must not turn a previously filtered offer into an available one.
    if Reception.shared.paywallAvailability != nil {
      Reception.shared.paywallAvailability = { _ in false }
    }
    Self.current = nil
  }

  private func snapshot() -> SnapshotMessage {
    Self.revision += 1
    let sdk = Reception.shared
    let appearance = (try? JSONSerialization.data(withJSONObject: Self.appearanceValues))
      .flatMap { String(data: $0, encoding: .utf8) }
    return SnapshotMessage(
      revision: Self.revision, settingRevisions: settingRevisions, isConfigured: Reception.isConfigured,
      unreadCount: Int64(sdk.unreadCount), isChatOpen: sdk.isChatOpen,
      availablePaywalls: sdk.availablePaywalls.map(PaywallValues.message),
      paywalls: sdk.paywalls.map(PaywallValues.message), appearanceJson: appearance ?? "{}",
      updatesAppBadge: sdk.updatesAppBadge, usesRemoteAppearance: sdk.usesRemoteAppearance,
      languageOverride: sdk.languageOverride, logLevel: ["off", "error", "info", "debug"][Reception.logLevel.rawValue])
  }

  private func applySetting(_ key: String, revision: Int64, update: () -> Void) -> SnapshotMessage {
    if connected && revision > (settingRevisions[key] ?? 0) {
      update()
      settingRevisions[key] = revision
    }
    return snapshot()
  }

  /// Publishes a snapshot now and after every change of the SDK state it reads.
  private func observe() {
    guard connected else { return }
    let token = observation
    withObservationTracking {
      let state = snapshot()
      send { try await $0.onState(state: state) }
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, self.connected, self.observation == token else { return }
        self.observe()
      }
    }
  }

  private func send(_ call: @escaping @MainActor (ReceptionFlutterApi) async throws -> Void) {
    guard connected else { return }
    let api = flutterApi
    Task { try? await call(api) }
  }

  private func send(_ event: ReceptionEvent) {
    let message: EventMessage
    switch event {
    case .identityRejected(let error):
      message = EventMessage(
        type: "identityRejected", error: ErrorMessage(code: error.code, status: Int64(error.status)))
    case .chatOpened: message = EventMessage(type: "chatOpened")
    case .messageSent: message = EventMessage(type: "messageSent")
    case .imageSent: message = EventMessage(type: "imageSent")
    case .reviewOpened: message = EventMessage(type: "reviewOpened")
    case .paywallOpened: message = EventMessage(type: "paywallOpened")
    case .dataDeleted: message = EventMessage(type: "dataDeleted")
    }
    send { try await $0.onEvent(event: message) }
  }

  // MARK: ReceptionHostApi. Pigeon calls these on the main thread.

  nonisolated func version() throws -> String { Reception.version }

  nonisolated func connect() throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      Self.current?.invalidate()
      Self.current = self
      connected = true
      // Dart counts setting revisions from zero again after a hot restart.
      settingRevisions = [:]
      Reception.shared.onEvent = { [weak self] event in self?.send(event) }
      observe()
      return snapshot()
    }
  }

  nonisolated func configure(appId: String, handlesNotifications: Bool) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      Reception.configure(appId: appId)
      ReceptionNotifications.shared.configured(handlesNotifications: handlesNotifications)
      return snapshot()
    }
  }

  nonisolated func configureForTesting(appId: String, serviceUrl: String) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      #if DEBUG
        if let url = URL(string: serviceUrl), let host = url.host, let scheme = url.scheme,
          ["localhost", "127.0.0.1", "::1"].contains(host), ["http", "https"].contains(scheme)
        {
          Reception.configure(appId: appId, serviceURL: url)
          ReceptionNotifications.shared.configured(handlesNotifications: true)
        }
      #endif
      return snapshot()
    }
  }

  nonisolated func identify(userId: String?, name: String?, email: String?) throws {
    MainActor.assumeIsolated { Reception.shared.identify(userId: userId, name: name, email: email) }
  }

  nonisolated func identifyToken(token: String) throws {
    MainActor.assumeIsolated { Reception.shared.identify(token: token) }
  }

  nonisolated func setMetadata(metadata: [String: String]) throws {
    MainActor.assumeIsolated { Reception.shared.setMetadata(metadata) }
  }

  nonisolated func logout() throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      Reception.shared.logout()
      ReceptionNotifications.shared.restorePush()
      return snapshot()
    }
  }

  nonisolated func deleteData() async throws -> DeleteResultMessage {
    await deleteDataOnMain()
  }

  private func deleteDataOnMain() async -> DeleteResultMessage {
    do {
      try await Reception.shared.deleteData()
      ReceptionNotifications.shared.restorePush()
      return DeleteResultMessage(state: snapshot())
    } catch let error as ReceptionError {
      return DeleteResultMessage(
        state: snapshot(), error: ErrorMessage(code: error.code, status: Int64(error.status)))
    } catch {
      return DeleteResultMessage(state: snapshot(), error: ErrorMessage(code: "bridge_error", status: 0))
    }
  }

  nonisolated func openChat() throws {
    MainActor.assumeIsolated { Reception.shared.openChat() }
  }

  nonisolated func closeChat() throws {
    MainActor.assumeIsolated { Reception.shared.closeChat() }
  }

  nonisolated func track(event: String, opensChat: Bool) throws {
    MainActor.assumeIsolated { Reception.shared.track(event, opensChat: opensChat) }
  }

  nonisolated func setPushToken(hexToken: String, environment: String) throws {
    MainActor.assumeIsolated {
      let environments: [String: Reception.PushEnvironment] = [
        "automatic": .automatic, "sandbox": .sandbox, "production": .production,
      ]
      guard let token = PushToken.decode(hexToken), let target = environments[environment] else { return }
      ReceptionNotifications.shared.setToken(token, environment: target)
    }
  }

  nonisolated func registerForPushIfAuthorized() async throws {
    await Reception.shared.registerForPushIfAuthorized()
  }

  nonisolated func handlePushNotification(conversationId: String, openChat: Bool) throws -> Bool {
    MainActor.assumeIsolated {
      Reception.shared.handlePushNotification(
        userInfo: ["reception": ["conversationId": conversationId]], openChat: openChat)
    }
  }

  nonisolated func setAppearance(json: String, revision: Int64) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      applySetting("appearance", revision: revision) { ReceptionAppearance.apply(json) }
    }
  }

  nonisolated func setUpdatesAppBadge(value: Bool, revision: Int64) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      applySetting("updatesAppBadge", revision: revision) { Reception.shared.updatesAppBadge = value }
    }
  }

  nonisolated func setUsesRemoteAppearance(value: Bool, revision: Int64) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      applySetting("usesRemoteAppearance", revision: revision) { Reception.shared.usesRemoteAppearance = value }
    }
  }

  nonisolated func setLanguageOverride(value: String?, revision: Int64) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      applySetting("languageOverride", revision: revision) { Reception.shared.languageOverride = value }
    }
  }

  nonisolated func setLogLevel(value: String, revision: Int64) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      applySetting("logLevel", revision: revision) {
        let levels: [String: Reception.LogLevel] = ["off": .off, "error": .error, "info": .info, "debug": .debug]
        if let level = levels[value] { Reception.logLevel = level }
      }
    }
  }

  nonisolated func setPaywalls(value: [PaywallMessage], revision: Int64) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      applySetting("paywalls", revision: revision) { Reception.shared.paywalls = value.map(PaywallValues.paywall) }
    }
  }

  nonisolated func setPaywallHandler(enabled: Bool) throws {
    MainActor.assumeIsolated {
      Reception.shared.onPaywall = enabled ? { [weak self] id in self?.send { try await $0.onPaywall(id: id) } } : nil
    }
  }

  nonisolated func setPaywallAvailability(enabled: Bool, generation: Int64) throws -> SnapshotMessage {
    MainActor.assumeIsolated {
      requests.cancelAll()
      guard enabled else {
        Reception.shared.paywallAvailability = nil
        return snapshot()
      }
      let api = flutterApi
      requests.ask = { id in (try? await api.checkPaywallAvailability(id: id, generation: generation)) ?? false }
      Reception.shared.paywallAvailability = { [weak self] id in
        guard let self, self.connected else { return false }
        return await self.requests.check(id)
      }
      return snapshot()
    }
  }

  nonisolated func refreshPaywalls(invalidate: Bool) throws {
    MainActor.assumeIsolated { Reception.shared.refreshPaywalls(invalidate: invalidate) }
  }
}
