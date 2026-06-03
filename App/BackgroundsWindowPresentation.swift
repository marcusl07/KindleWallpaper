import Foundation

enum BackgroundsWindowPresentation {
    static func requestShowWindow(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .leafShowBackgroundsWindow, object: nil)
    }

    static func notifyCollectionChanged(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .leafBackgroundCollectionDidChange, object: nil)
    }
}

extension Notification.Name {
    static let leafShowBackgroundsWindow = Notification.Name("leafShowBackgroundsWindow")
    static let leafBackgroundCollectionDidChange = Notification.Name("leafBackgroundCollectionDidChange")
}
