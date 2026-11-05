import Foundation

public enum CourseDisplayMode: String, Codable, CaseIterable, Sendable {
    case code, name, codeAndName, custom
    public var label: String {
        switch self {
        case .code: "Course code"
        case .name: "Course name"
        case .codeAndName: "Code + name"
        case .custom: "Custom name"
        }
    }
}
public struct CourseAppearance: Codable, Sendable, Equatable {
    public var mode: CourseDisplayMode?
    public var alias: String
    public init(mode: CourseDisplayMode? = nil, alias: String = "") { self.mode = mode; self.alias = alias }
    public func title(for course: Course, defaultMode: CourseDisplayMode) -> String {
        let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode ?? defaultMode {
        case .code: return code.isEmpty ? name : code
        case .name: return name.isEmpty ? code : name
        case .codeAndName: return code.isEmpty || code == name ? name : name.isEmpty ? code : "\(code) · \(name)"
        case .custom:
            let custom = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? (code.isEmpty ? name : code) : custom
        }
    }
}
