#if canImport(ServiceManagement)
import ServiceManagement
#endif

enum LaunchAtLoginService {
    static func currentEnabled() -> Bool {
#if canImport(ServiceManagement)
        return SMAppService.mainApp.status == .enabled
#else
        return false
#endif
    }

    static func refreshEnabled() -> Bool {
        currentEnabled()
    }

    static func setEnabled(_ enabled: Bool) throws {
#if canImport(ServiceManagement)
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            if enabled {
                throw AppState.LaunchAtLoginError.registerFailed(error.localizedDescription)
            } else {
                throw AppState.LaunchAtLoginError.unregisterFailed(error.localizedDescription)
            }
        }
#else
        throw AppState.LaunchAtLoginError.unsupported
#endif
    }
}
