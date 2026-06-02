import Foundation

enum BackgroundsWindowPresentation {
    static func requestShowWindow(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .kindleWallShowBackgroundsWindow, object: nil)
    }

    static func notifyCollectionChanged(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .kindleWallBackgroundCollectionDidChange, object: nil)
    }
}

extension Notification.Name {
    static let kindleWallShowBackgroundsWindow = Notification.Name("kindleWallShowBackgroundsWindow")
    static let kindleWallBackgroundCollectionDidChange = Notification.Name("kindleWallBackgroundCollectionDidChange")
}
