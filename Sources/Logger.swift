import Foundation

/// ファイルベースの診断ログ。unified log では NSLog の内容が <private> に秘匿されて
/// 外部から読めないため、~/Library/Logs/MagicMouseToolkit.log にも平文で書き出す。
enum MMTLog {
    private static let maxFileSize: UInt64 = 1_048_576

    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MagicMouseToolkit.log")
    }()

    private static let queue = DispatchQueue(label: "com.mori0818.magicmousetoolkit.log", qos: .utility)

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        NSLog("[MagicMouseToolkit] %@", message)
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded(adding: UInt64(data.count))
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static func rotateIfNeeded(adding bytes: UInt64) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentSize + bytes > maxFileSize else { return }

        let rotatedURL = url.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: url, to: rotatedURL)
    }
}
