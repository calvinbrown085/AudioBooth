import Combine
import Foundation

@Observable
public final class Server: @unchecked Sendable {
  public let id: String
  public let baseURL: URL
  public internal(set) var token: Credentials
  public internal(set) var customHeaders: [String: String]
  public internal(set) var alias: String?
  public internal(set) var alternativeURL: URL?
  public var urlMode: URLMode

  public enum URLMode {
    case primary
    case alternative
    case fallback
  }

  public var isUsingAlternativeURL: Bool {
    urlMode == .alternative || urlMode == .fallback
  }

  public var activeURL: URL {
    isUsingAlternativeURL ? alternativeURL ?? baseURL : baseURL
  }

  public enum Status {
    case connected
    case connectionError
    case authenticationError
  }

  public var status: Status = .connected

  @ObservationIgnored
  private lazy var credentialsActor = CredentialsActor(server: self)

  public var freshToken: Credentials {
    get async throws {
      try await credentialsActor.freshCredentials
    }
  }

  public let storage: UserDefaults

  enum StorageKeys {
    static let username = "username"
    static let permissions = "permissions"
    static let userType = "userType"
  }

  public var username: String? {
    get { storage.string(forKey: StorageKeys.username) }
    set {
      if let newValue {
        storage.set(newValue, forKey: StorageKeys.username)
      } else {
        storage.removeObject(forKey: StorageKeys.username)
      }
    }
  }

  public var permissions: User.Permissions? {
    get {
      guard let data = storage.data(forKey: StorageKeys.permissions) else { return nil }
      return try? JSONDecoder().decode(User.Permissions.self, from: data)
    }
    set {
      if let newValue, let data = try? JSONEncoder().encode(newValue) {
        storage.set(data, forKey: StorageKeys.permissions)
      } else {
        storage.removeObject(forKey: StorageKeys.permissions)
      }
    }
  }

  public var userType: UserType? {
    get {
      guard let raw = storage.string(forKey: StorageKeys.userType) else { return nil }
      return UserType(rawValue: raw)
    }
    set {
      if let newValue {
        storage.set(newValue.rawValue, forKey: StorageKeys.userType)
      } else {
        storage.removeObject(forKey: StorageKeys.userType)
      }
    }
  }

  public func clearStorage() {
    storage.removePersistentDomain(forName: "connection.\(id)")
  }

  public init(connection: Connection) {
    self.id = connection.id
    self.baseURL = connection.serverURL
    self.token = connection.token
    self.customHeaders = connection.customHeaders
    self.alias = connection.alias
    self.alternativeURL = connection.alternativeURL
    self.urlMode = connection.isUsingAlternativeURL ? .alternative : .primary
    self.storage = UserDefaults(suiteName: "connection.\(connection.id)") ?? .standard
  }
}
