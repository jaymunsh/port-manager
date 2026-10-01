import Foundation

/// Builds device trees from `system_profiler` JSON output.
/// Runs off the main actor; safe to call from a detached task.
struct USBProvider: Sendable {
    func usbTree() throws -> [DeviceNode] {
        try tree(forDataType: "SPUSBDataType")
    }

    func thunderboltTree() throws -> [DeviceNode] {
        try tree(forDataType: "SPThunderboltDataType")
    }

    private func tree(forDataType dataType: String) throws -> [DeviceNode] {
        let result = try Shell.run("/usr/sbin/system_profiler", [dataType, "-json"], timeout: 30)
        try result.requireSuccess(command: "system_profiler")
        guard let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buses = root[dataType] as? [[String: Any]] else {
            throw ShellError.commandFailed("system_profiler", result.status, "Invalid device report")
        }
        return buses.map { node(from: $0, kind: .bus) }
    }

    private func node(from dict: [String: Any], kind: DeviceNode.Kind) -> DeviceNode {
        let name = (dict["_name"] as? String)
            ?? (dict["device_name"] as? String)
            ?? "Unknown"
        let children = (dict["_items"] as? [[String: Any]] ?? [])
            .map { node(from: $0, kind: .device) }
        return DeviceNode(
            name: name,
            detail: detailString(from: dict),
            kind: children.isEmpty ? kind : (kind == .bus ? .bus : .hub),
            children: children
        )
    }

    private func detailString(from dict: [String: Any]) -> String {
        var parts: [String] = []
        let interesting: [(key: String, label: String)] = [
            ("manufacturer", ""), ("vendor_id", ""), ("product_id", ""),
            ("serial_num", "SN"), ("serial_num_holder", "SN"),
            ("speed", ""), ("bus_power", "bus power"),
            ("bus_power_used", "used"), ("extra_current_used", "extra"),
            ("bcd_device", "bcd"), ("location_id", "loc"),
            ("switch_uid", "UID"), ("route_string", "route"),
            ("device_name", ""), ("vendor_name", ""),
            ("mode", "mode"), ("status", "")
        ]
        for (key, label) in interesting {
            if let value = dict[key] {
                let text = "\(value)".trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                parts.append(label.isEmpty ? text : "\(label) \(text)")
            }
        }
        return parts.joined(separator: "  ·  ")
    }
}
