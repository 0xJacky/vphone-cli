import Foundation

// MARK: - Wire

/// The host end of vphoned's terminal protocol (`GuestTerminalWire` in the
/// daemon). One WebSocket on `/v1/terminal` per shell: binary frames are
/// terminal bytes both ways, text frames are JSON control messages. The shell
/// lives exactly as long as the connection.
enum VPhoneTerminalWire {
    static let path = "/v1/terminal"
    /// The size vphoned accepts for either dimension.
    static let sizeRange: ClosedRange<Int> = 1 ... 1000
    /// Input is sent in frames of at most this many bytes.
    static let maximumInputFrame = 64 * 1024

    struct Size: Equatable, Sendable {
        var columns: Int
        var rows: Int

        static let fallback = Size(columns: 80, rows: 24)

        init(columns: Int, rows: Int) {
            self.columns = min(max(columns, sizeRange.lowerBound), sizeRange.upperBound)
            self.rows = min(max(rows, sizeRange.lowerBound), sizeRange.upperBound)
        }
    }

    /// The request target that opens a shell of `size`, with the machine's
    /// name for its prompt.
    static func requestTarget(size: Size, machineName: String?) -> String {
        var components = URLComponents()
        components.path = path
        var items = [
            URLQueryItem(name: "cols", value: String(size.columns)),
            URLQueryItem(name: "rows", value: String(size.rows)),
        ]
        if let machineName, !machineName.isEmpty {
            items.append(URLQueryItem(name: "name", value: machineName))
        }
        components.queryItems = items
        return components.percentEncodedPath + "?" + (components.percentEncodedQuery ?? "")
    }

    /// The control message that resizes the terminal.
    static func resizeMessage(_ size: Size) -> Data {
        let object: [String: Any] = ["type": "resize", "cols": size.columns, "rows": size.rows]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// `input` cut into frames vphoned takes whole.
    static func inputFrames(_ input: Data) -> [Data] {
        guard input.count > maximumInputFrame else { return input.isEmpty ? [] : [input] }
        return stride(from: input.startIndex, to: input.endIndex, by: maximumInputFrame).map { start in
            input[start ..< min(start + maximumInputFrame, input.endIndex)]
        }
    }

    // MARK: Guest Messages

    /// A control message from vphoned.
    enum Message: Equatable, Sendable {
        /// The shell runs.
        case started(pid: Int, shell: String, layout: String?, user: String?)
        /// The shell ended with an exit status, or was killed by a signal.
        case exited(status: Int?, signal: Int?)
        /// No shell could start; the connection closes after this.
        case failed(code: String, message: String)

        /// Nil for anything that is not a known message, which the host ignores.
        init?(json data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String
            else { return nil }
            switch type {
            case "started":
                self = .started(
                    pid: (object["pid"] as? NSNumber)?.intValue ?? 0,
                    shell: object["shell"] as? String ?? "",
                    layout: object["layout"] as? String,
                    user: object["user"] as? String,
                )
            case "exit":
                self = .exited(
                    status: (object["status"] as? NSNumber)?.intValue,
                    signal: (object["signal"] as? NSNumber)?.intValue,
                )
            case "error":
                self = .failed(
                    code: object["code"] as? String ?? "error",
                    message: object["message"] as? String ?? "The guest could not start a shell.",
                )
            default:
                return nil
            }
        }
    }
}
