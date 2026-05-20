import Logging

enum AppLogger {
  static let persistence = Logger(label: "models.persistence")
  static let sync = Logger(label: "models.sync")
}
