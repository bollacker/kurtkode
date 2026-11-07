import os

/// App logging. Read with: log show --last 5m --predicate 'subsystem == "org.mlcommons.kurt.kurtkode"'
enum Log {
    static let app = Logger(subsystem: "org.mlcommons.kurt.kurtkode", category: "app")
    static let agent = Logger(subsystem: "org.mlcommons.kurt.kurtkode", category: "agent")
}
