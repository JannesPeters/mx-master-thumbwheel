import Foundation

public struct MappingValidationIssue: Equatable, CustomStringConvertible {
    public enum Kind: Equatable {
        case duplicateClick(button: InputButton, click: ButtonClickKind)
        case duplicateHold(button: InputButton)
        case duplicateWheel(source: WheelMappingSource)
        case invalidValue(String)
    }

    public var kind: Kind
    public var mappingID: UUID?
    public var description: String

    public init(kind: Kind, mappingID: UUID? = nil, description: String? = nil) {
        self.kind = kind
        self.mappingID = mappingID
        self.description = description ?? Self.defaultDescription(for: kind)
    }

    private static func defaultDescription(for kind: Kind) -> String {
        switch kind {
        case let .duplicateClick(button, click):
            return "\(button.displayName) already has a \(click.displayName.lowercased()) click mapping."
        case let .duplicateHold(button):
            return "\(button.displayName) already has a hold mapping."
        case let .duplicateWheel(source):
            return "\(source.displayName) already has a wheel mapping."
        case let .invalidValue(message):
            return message
        }
    }
}

public enum MappingValidator {
    public static func validate(_ document: ConfigurationDocument) -> [MappingValidationIssue] {
        var issues: [MappingValidationIssue] = []
        var clickKeys: [String: UUID] = [:]
        var holdKeys: [String: UUID] = [:]
        var wheelKeys: [String: UUID] = [:]

        for mapping in document.buttonClicks {
            let key = "\(mapping.button.id)|\(mapping.click.rawValue)"
            if clickKeys[key] != nil {
                issues.append(
                    MappingValidationIssue(
                        kind: .duplicateClick(button: mapping.button, click: mapping.click),
                        mappingID: mapping.id
                    )
                )
            } else {
                clickKeys[key] = mapping.id
            }

            issues.append(contentsOf: validate(action: mapping.action, mappingID: mapping.id))
        }

        for mapping in document.buttonHolds {
            let key = mapping.button.id
            if holdKeys[key] != nil {
                issues.append(
                    MappingValidationIssue(
                        kind: .duplicateHold(button: mapping.button),
                        mappingID: mapping.id
                    )
                )
            } else {
                holdKeys[key] = mapping.id
            }

            guard mapping.action.pointsPerSecond.isFinite,
                  mapping.action.pointsPerSecond > 0 else {
                issues.append(
                    MappingValidationIssue(
                        kind: .invalidValue("Hold speed must be greater than zero."),
                        mappingID: mapping.id
                    )
                )
                continue
            }
            if !mapping.action.accelerationDuration.isFinite
                || !mapping.action.releaseDuration.isFinite
                || mapping.action.accelerationDuration < 0
                || mapping.action.releaseDuration < 0 {
                issues.append(
                    MappingValidationIssue(
                        kind: .invalidValue("Hold timing values cannot be negative."),
                        mappingID: mapping.id
                    )
                )
            }
        }

        for mapping in document.wheelMappings {
            let key = mapping.source.rawValue
            if wheelKeys[key] != nil {
                issues.append(
                    MappingValidationIssue(
                        kind: .duplicateWheel(source: mapping.source),
                        mappingID: mapping.id
                    )
                )
            } else {
                wheelKeys[key] = mapping.id
            }
        }

        return issues
    }

    public static func isValid(_ document: ConfigurationDocument) -> Bool {
        validate(document).isEmpty
    }

    private static func validate(
        action: ScrollActionOptions,
        mappingID: UUID
    ) -> [MappingValidationIssue] {
        var issues: [MappingValidationIssue] = []
        switch action.amount {
        case let .fixed(points):
            if !points.isFinite || points <= 0 {
                issues.append(
                    MappingValidationIssue(
                        kind: .invalidValue("Scroll distance must be greater than zero."),
                        mappingID: mappingID
                    )
                )
            }
        case .page:
            break
        }

        if !action.duration.isFinite || action.duration < 0 {
            issues.append(
                MappingValidationIssue(
                    kind: .invalidValue("Scroll duration cannot be negative."),
                    mappingID: mappingID
                )
            )
        }
        return issues
    }
}

public protocol ConfigurationStorage {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String) throws
}

public struct UserDefaultsConfigurationStorage: ConfigurationStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data, forKey key: String) throws {
        defaults.set(data, forKey: key)
    }
}

public final class ConfigurationStore {
    public static let storageKey = "ThumbwheelRemapper.Configuration.v1"

    public typealias Logger = (String) -> Void

    private let storage: ConfigurationStorage
    private let key: String
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        storage: ConfigurationStorage = UserDefaultsConfigurationStorage(),
        key: String = ConfigurationStore.storageKey,
        logger: @escaping Logger = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    ) {
        self.storage = storage
        self.key = key
        self.logger = logger

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() -> ConfigurationDocument {
        guard let data = storage.data(forKey: key) else {
            return .defaults
        }

        do {
            let document = try decoder.decode(ConfigurationDocument.self, from: data)
            guard document.version == ConfigurationDocument.currentVersion else {
                logger(
                    "Thumbwheel Remapper ignored configuration at \(key): unsupported version \(document.version)."
                )
                return .defaults
            }
            let issues = MappingValidator.validate(document)
            guard issues.isEmpty else {
                logger(
                    "Thumbwheel Remapper ignored configuration at \(key): \(issues.map(\.description).joined(separator: " "))"
                )
                return .defaults
            }
            return document
        } catch {
            logger("Thumbwheel Remapper could not decode configuration at \(key): \(error).")
            return .defaults
        }
    }

    @discardableResult
    public func save(_ document: ConfigurationDocument) -> Bool {
        guard document.version == ConfigurationDocument.currentVersion else {
            logger(
                "Thumbwheel Remapper refused to save configuration at \(key): unsupported version \(document.version)."
            )
            return false
        }
        let issues = MappingValidator.validate(document)
        guard issues.isEmpty else {
            logger(
                "Thumbwheel Remapper refused to save configuration at \(key): \(issues.map(\.description).joined(separator: " "))"
            )
            return false
        }

        do {
            try storage.set(encoder.encode(document), forKey: key)
            return true
        } catch {
            logger("Thumbwheel Remapper could not save configuration at \(key): \(error).")
            return false
        }
    }
}
