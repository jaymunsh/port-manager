import Foundation

/// The same ordering applies to normal and forced unmounts: eject is allowed
/// only after DiskArbitration confirms that the whole device is unmounted.
@MainActor
enum EjectOperation {
    static func perform(
        unmount: () async -> Result<Void, DiskServiceError>,
        eject: () async -> Result<Void, DiskServiceError>
    ) async -> Result<Void, DiskServiceError> {
        let result = await unmount()
        if case .failure = result { return result }
        return await eject()
    }
}
