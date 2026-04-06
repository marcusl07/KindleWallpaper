#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t20.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/verify_t20.swift" <<'SWIFT'
import Foundation
#if canImport(AppKit)
import AppKit

@main
struct VerifyT20 {
    static func main() {
        testHandleMountedVolumeSkipsImportWhenNoClippingsFileIsFound()
        testHandleMountedVolumePublishesSuccessStatus()
        testHandleMountedVolumePublishesLibraryUpToDateStatus()
        testHandleMountedVolumePublishesFailureStatus()
        testHandleMountedVolumeRejectsOversizedClippingsFile()
        testMountListenerRegistersAndStopsObservingNotifications()
        print("T20 verification passed")
    }

    private static func testHandleMountedVolumeSkipsImportWhenNoClippingsFileIsFound() {
        let volumeURL = URL(fileURLWithPath: "/tmp/Kindle")
        var importCallCount = 0
        var publishedStatuses: [VolumeWatcher.ImportStatus] = []

        VolumeWatcher.handleMountedVolume(
            volumeURL,
            findClippingsFile: { _ in nil },
            importFile: { _ in
                importCallCount += 1
                return VolumeWatcher.ImportPayload(
                    newHighlightCount: 0,
                    error: nil,
                    parseWarningCount: 0,
                    skippedEntryCount: 0,
                    warningMessages: []
                )
            },
            publishImportStatus: { status in
                publishedStatuses.append(status)
            }
        )

        expect(importCallCount == 0, "Expected no import when clippings file is missing")
        expect(publishedStatuses.isEmpty, "Expected no status update when import does not run")
    }

    private static func testHandleMountedVolumePublishesSuccessStatus() {
        let volumeURL = URL(fileURLWithPath: "/tmp/Kindle")
        let clippingsURL = URL(fileURLWithPath: "/tmp/Kindle/Documents/My Clippings.txt")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        var importedURL: URL?
        var publishedStatus: VolumeWatcher.ImportStatus?

        VolumeWatcher.handleMountedVolume(
            volumeURL,
            findClippingsFile: { _ in clippingsURL },
            importFile: { url in
                importedURL = url
                return VolumeWatcher.ImportPayload(
                    newHighlightCount: 2,
                    error: nil,
                    parseWarningCount: 2,
                    skippedEntryCount: 0,
                    warningMessages: [
                        "Could not parse Added on date in entry: \"Book One (Author One) - Your Highlight on page 1\"",
                        "Could not parse Added on date in entry: \"Book Two (Author Two) - Your Highlight on page 2\""
                    ]
                )
            },
            publishImportStatus: { status in
                publishedStatus = status
            },
            now: { fixedDate }
        )

        expect(importedURL == clippingsURL, "Expected import to be called with resolved clippings URL")
        guard let publishedStatus else {
            fail("Expected an import status to be published on successful import")
        }

        expect(publishedStatus.isError == false, "Expected success status to be non-error")
        expect(publishedStatus.message.hasPrefix("Last synced: "), "Expected success message prefix")
        expect(
            publishedStatus.message.hasSuffix("2 new highlights added (2 parse warnings)"),
            "Expected success message to include new highlight count and parse warning count"
        )
        expect(
            publishedStatus.warningDetails.count == 2,
            "Expected success status to retain warning details"
        )
    }

    private static func testHandleMountedVolumePublishesLibraryUpToDateStatus() {
        let volumeURL = URL(fileURLWithPath: "/tmp/Kindle")
        let clippingsURL = URL(fileURLWithPath: "/tmp/Kindle/My Clippings.txt")
        var publishedStatus: VolumeWatcher.ImportStatus?

        VolumeWatcher.handleMountedVolume(
            volumeURL,
            findClippingsFile: { _ in clippingsURL },
            importFile: { _ in
                VolumeWatcher.ImportPayload(
                    newHighlightCount: 0,
                    error: nil,
                    parseWarningCount: 1,
                    skippedEntryCount: 0,
                    warningMessages: [
                        "Could not parse Added on date in entry: \"Book Three (Author Three) - Your Highlight on page 3\""
                    ]
                )
            },
            publishImportStatus: { status in
                publishedStatus = status
            }
        )

        expect(
            publishedStatus == VolumeWatcher.ImportStatus(
                message: "Library up to date (1 parse warning)",
                isError: false,
                warningDetails: [
                    "Could not parse Added on date in entry: \"Book Three (Author Three) - Your Highlight on page 3\""
                ]
            ),
            "Expected parse warning suffix when no new highlights are imported"
        )
    }

    private static func testHandleMountedVolumePublishesFailureStatus() {
        let fixedDate = Date(timeIntervalSince1970: 0)

        let resultOne = VolumeWatcher.makeImportStatus(
            from: VolumeWatcher.ImportPayload(
                newHighlightCount: 0,
                error: "Could not read file",
                parseWarningCount: 0,
                skippedEntryCount: 0,
                warningMessages: []
            ),
            now: fixedDate
        )
        expect(
            resultOne == VolumeWatcher.ImportStatus(
                message: "Import failed: Could not read file",
                isError: true,
                warningDetails: []
            ),
            "Expected failure status to be prefixed with 'Import failed:'"
        )

        let resultTwo = VolumeWatcher.makeImportStatus(
            from: VolumeWatcher.ImportPayload(
                newHighlightCount: 0,
                error: "Import failed: malformed clipping",
                parseWarningCount: 0,
                skippedEntryCount: 0,
                warningMessages: []
            ),
            now: fixedDate
        )
        expect(
            resultTwo == VolumeWatcher.ImportStatus(
                message: "Import failed: malformed clipping",
                isError: true,
                warningDetails: []
            ),
            "Expected pre-prefixed errors to avoid duplicate prefixes"
        )
    }

    private static func testHandleMountedVolumeRejectsOversizedClippingsFile() {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kindlewall-t20-\(UUID().uuidString)", isDirectory: true)
        let clippingsURL = tempRoot.appendingPathComponent("My Clippings.txt", isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try Data(repeating: 0x61, count: 21 * 1024 * 1024).write(to: clippingsURL)
        } catch {
            fail("Failed to create oversized clippings fixture: \(error)")
        }
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        var importCalled = false
        var publishedStatus: VolumeWatcher.ImportStatus?

        VolumeWatcher.handleMountedVolume(
            tempRoot,
            findClippingsFile: { _ in clippingsURL },
            importFile: { _ in
                importCalled = true
                return VolumeWatcher.ImportPayload(
                    newHighlightCount: 0,
                    error: nil,
                    parseWarningCount: 0,
                    skippedEntryCount: 0,
                    warningMessages: []
                )
            },
            publishImportStatus: { status in
                publishedStatus = status
            }
        )

        expect(importCalled == false, "Expected oversized file to be rejected before import is attempted")
        expect(
            publishedStatus == VolumeWatcher.ImportStatus(
                message: "Import failed: clippings file is larger than 20 MB.",
                isError: true,
                warningDetails: []
            ),
            "Expected oversized file to surface explicit size-limit error"
        )
    }

    private static func testMountListenerRegistersAndStopsObservingNotifications() {
        let notificationCenter = NotificationCenter()
        let mountNotificationName = Notification.Name("verify.mount")
        let userInfoKey = "VolumeURLKey"
        let volumeURL = URL(fileURLWithPath: "/tmp/Kindle")
        let clippingsURL = URL(fileURLWithPath: "/tmp/Kindle/Documents/My Clippings.txt")

        var resolvedVolumes: [URL] = []
        var publishedStatuses: [VolumeWatcher.ImportStatus] = []

        let listener = VolumeWatcher.MountListener(
            notificationCenter: notificationCenter,
            mountNotificationName: mountNotificationName,
            volumeURLUserInfoKey: userInfoKey,
            findClippingsFile: { observedVolumeURL in
                resolvedVolumes.append(observedVolumeURL)
                return clippingsURL
            },
            importFile: { _ in
                VolumeWatcher.ImportPayload(
                    newHighlightCount: 1,
                    error: nil,
                    parseWarningCount: 0,
                    skippedEntryCount: 0,
                    warningMessages: []
                )
            },
            publishImportStatus: { status in
                publishedStatuses.append(status)
            },
            dispatchWork: { work in
                work()
            },
            now: { Date(timeIntervalSince1970: 1_700_000_100) }
        )

        listener.start()
        listener.start()
        notificationCenter.post(name: mountNotificationName, object: nil, userInfo: [userInfoKey: volumeURL])

        expect(resolvedVolumes == [volumeURL], "Expected listener to process mount exactly once despite duplicate start() calls")
        expect(publishedStatuses.count == 1, "Expected one published status after one mount event")

        listener.stop()
        notificationCenter.post(name: mountNotificationName, object: nil, userInfo: [userInfoKey: volumeURL])
        expect(resolvedVolumes.count == 1, "Expected listener to stop processing events after stop()")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

#else
@main
struct VerifyT20 {
    static func main() {
        print("T20 verification skipped: AppKit unavailable")
    }
}
#endif
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$TMP_DIR/verify_t20.swift" \
  -o "$TMP_DIR/t20_runner"

"$TMP_DIR/t20_runner"
