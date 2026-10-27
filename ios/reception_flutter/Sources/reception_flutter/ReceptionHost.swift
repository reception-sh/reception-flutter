import Foundation
import Observation

/// Implements the Pigeon host API for one Flutter engine. The SDK is a process-wide singleton, so only the most
/// recently connected engine receives state, events and callbacks; `connect()` replaces any earlier connection,
/// including the same engine's after a hot restart.
@MainActor
internal final class ReceptionHost: @preconcurrency ReceptionHostApi {
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

  /// Only the current connection may change SDK callbacks; a replaced engine or connection must not.
  private var isCurrent: Bool { connected && Self.current === self }

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

  func connect() throws -> SnapshotMessage {
    Self.current?.invalidate()
    Self.current = self
    connected = true
    // Dart counts setting revisions from zero again after a hot restart.
    settingRevisions = [:]
    Reception.shared.onEvent = { [weak self] event in self?.send(event) }
    observe()
    return snapshot()
  }

  func configure(appId: String, handlesNotifications: Bool) throws -> SnapshotMessage {
    // A rejected App ID leaves any earlier configuration, and its push ownership, unchanged.
    guard ReceptionAPI.accepts(appId: appId) else { return snapshot() }
    Reception.configure(appId: appId)
    ReceptionNotifications.shared.configured(handlesNotifications: handlesNotifications)
    return snapshot()
  }

  func configureForTesting(appId: String, serviceUrl: String) throws -> SnapshotMessage {
    #if DEBUG && targetEnvironment(simulator)
      if let url = URL(string: serviceUrl), let host = url.host, let scheme = url.scheme,
        ["localhost", "127.0.0.1", "::1"].contains(host), ["http", "https"].contains(scheme)
      {
        Reception.configure(appId: appId, serviceURL: url)
        ReceptionNotifications.shared.configured(handlesNotifications: true)
      }
    #endif
    return snapshot()
  }

  func identify(userId: String?, name: String?, email: String?) throws {
    Reception.shared.identify(userId: userId, name: name, email: email)
  }

  func identifyToken(token: String) throws {
    Reception.shared.identify(token: token)
  }

  func setMetadata(metadata: [String: String]) throws {
    Reception.shared.setMetadata(metadata)
  }

  func logout() throws -> SnapshotMessage {
    Reception.shared.logout()
    ReceptionNotifications.shared.restorePush()
    return snapshot()
  }

  func deleteData(completion: @escaping (Result<DeleteResultMessage, Error>) -> Void) {
    Task { completion(.success(await deleteDataResult())) }
  }

  private func deleteDataResult() async -> DeleteResultMessage {
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

  func openChat() throws {
    Reception.shared.openChat()
  }

  func closeChat() throws {
    Reception.shared.closeChat()
  }

  func track(event: String, opensChat: Bool) throws {
    Reception.shared.track(event, opensChat: opensChat)
  }

  func setPushToken(hexToken: String, environment: String) throws {
    let environments: [String: Reception.PushEnvironment] = [
      "automatic": .automatic, "sandbox": .sandbox, "production": .production,
    ]
    guard let token = PushToken.decode(hexToken), let target = environments[environment] else { return }
    ReceptionNotifications.shared.setToken(token, environment: target)
  }

  func registerForPushIfAuthorized(completion: @escaping (Result<Void, Error>) -> Void) {
    Task {
      await Reception.shared.registerForPushIfAuthorized()
      completion(.success(()))
    }
  }

  func handlePushNotification(conversationId: String, openChat: Bool) throws -> Bool {
    Reception.shared.handlePushNotification(
      userInfo: ["reception": ["conversationId": conversationId]], openChat: openChat)
  }

  func setAppearance(json: String, revision: Int64) throws -> SnapshotMessage {
    applySetting("appearance", revision: revision) { ReceptionAppearance.apply(json) }
  }

  func setUpdatesAppBadge(value: Bool, revision: Int64) throws -> SnapshotMessage {
    applySetting("updatesAppBadge", revision: revision) { Reception.shared.updatesAppBadge = value }
  }

  func setUsesRemoteAppearance(value: Bool, revision: Int64) throws -> SnapshotMessage {
    applySetting("usesRemoteAppearance", revision: revision) { Reception.shared.usesRemoteAppearance = value }
  }

  func setLanguageOverride(value: String?, revision: Int64) throws -> SnapshotMessage {
    applySetting("languageOverride", revision: revision) { Reception.shared.languageOverride = value }
  }

  func setLogLevel(value: String, revision: Int64) throws -> SnapshotMessage {
    applySetting("logLevel", revision: revision) {
      let levels: [String: Reception.LogLevel] = ["off": .off, "error": .error, "info": .info, "debug": .debug]
      if let level = levels[value] { Reception.logLevel = level }
    }
  }

  func setPaywalls(value: [PaywallMessage], revision: Int64) throws -> SnapshotMessage {
    applySetting("paywalls", revision: revision) { Reception.shared.paywalls = value.map(PaywallValues.paywall) }
  }

  func setPaywallHandler(enabled: Bool) throws {
    guard isCurrent else { return }
    Reception.shared.onPaywall = enabled ? { [weak self] id in self?.send { try await $0.onPaywall(id: id) } } : nil
  }

  func setPaywallAvailability(enabled: Bool, generation: Int64) throws -> SnapshotMessage {
    guard isCurrent else { return snapshot() }
    requests.cancelAll()
    guard enabled else {
      Reception.shared.paywallAvailability = nil
      return snapshot()
    }
    requests.emit = { [weak self] requestId, id in
      self?.send { try await $0.requestPaywallAvailability(requestId: requestId, id: id, generation: generation) }
    }
    Reception.shared.paywallAvailability = { [weak self] id in
      guard let self, self.connected else { return false }
      return await self.requests.check(id)
    }
    return snapshot()
  }

  func resolvePaywallAvailability(requestId: String, allowed: Bool) throws {
    requests.resolve(requestId, allowed: allowed)
  }

  func refreshPaywalls(invalidate: Bool) throws {
    Reception.shared.refreshPaywalls(invalidate: invalidate)
  }
}
