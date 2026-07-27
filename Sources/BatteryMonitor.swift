import IOKit

/// IORegistry から外部 Magic Mouse のバッテリー残量を取得する。
/// メニューを開いたタイミングでのみ呼ぶため、ポーリングやキャッシュは持たない。
enum BatteryMonitor {
    private static let knownMagicMouseProductIDs: Set<Int> = [617, 781]

    /// 外部マウスのバッテリー残量（%）。未接続または取得不能なら nil。
    static func mouseBatteryPercent() -> Int? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [(percent: Int, productID: Int?)] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let currentService = service
            service = IOIteratorNext(iterator)
            defer { IOObjectRelease(currentService) }

            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(
                    currentService,
                    key as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue()
            }

            let builtIn = (property("Built-In") as? Bool) ?? false
            guard !builtIn, let percent = property("BatteryPercent") as? Int else { continue }
            candidates.append((percent: percent, productID: property("ProductID") as? Int))
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0].percent }

        return candidates.first {
            guard let productID = $0.productID else { return false }
            return knownMagicMouseProductIDs.contains(productID)
        }?.percent ?? candidates[0].percent
    }
}
