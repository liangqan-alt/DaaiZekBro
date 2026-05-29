import Foundation

enum AppLaunchConfiguration {
    static var isUITesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-dz-ui-testing")
        #else
        return false
        #endif
    }

    static var forcesModelContainerFailure: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-dz-force-container-failure")
        #else
        return false
        #endif
    }

    static var uiFixtureName: String? {
        #if DEBUG
        guard isUITesting else {
            return nil
        }

        return value(after: "-dz-ui-fixture")
        #else
        return nil
        #endif
    }

    static func now() -> Date {
        fixedNow ?? Date()
    }

    private static var fixedNow: Date? {
        #if DEBUG
        guard isUITesting else {
            return nil
        }

        guard let value = value(after: "-dz-now") else {
            return nil
        }

        return ISO8601DateFormatter().date(from: value)
        #else
        return nil
        #endif
    }

    private static func value(after key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return arguments[valueIndex]
    }
}
