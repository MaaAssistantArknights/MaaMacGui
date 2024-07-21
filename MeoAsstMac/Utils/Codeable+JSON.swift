import Foundation

extension Decodable {
    static func fromJson(_ json: Any) -> Result<Self, Error> {
        do {
            if JSONSerialization.isValidJSONObject(json) {
                // According to documentation, exception thrown by this method can't be caught. Calling `isValidJSONObject` is required to avoid crash.
                let data = try JSONSerialization.data(withJSONObject: json, options: [])
                return try .success(JSONDecoder().decode(Self.self, from: data))
            }
            else {
                // If top level object is not array or dictionary, it is considered as invalid JSONObject by Apple. We need to handle it manually.
                // The top level object must be string or number (bool included)
                if json is String, let stringResult = json as? Self {
                    return .success(stringResult)
                }
                else if json is NSNumber, let numberResult = json as? Self {
                    return .success(numberResult)
                }
                else {
                    return .failure(InvalidJSONObjectError())
                }
            }
        }
        catch {
            return .failure(error)
        }
    }
}

extension Encodable {
    func jsonString(withoutEscapingSlashes: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if withoutEscapingSlashes {
            encoder.outputFormatting = .withoutEscapingSlashes
        }

        let data = try encoder.encode(self)

        let parsedString = String(decoding: data, as: Unicode.UTF8.self)
        return parsedString
    }
}

struct InvalidJSONObjectError: Error {}

public enum JSONHelper {
    private static let jsonDecoder = JSONDecoder()

    public static func json<T: Decodable>(from content: String?, of: T.Type) -> T? {
        guard let data = content?.data(using: .utf8) else {
            return nil
        }
        do {
            return try JSONHelper.jsonDecoder.decode(T.self, from: data)
        }
        catch {
            assertionFailure("Cannot decode json: \(error)")
            return nil
        }
    }
}
