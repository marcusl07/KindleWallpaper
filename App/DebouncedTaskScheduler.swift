import Foundation

struct AppAsyncSleep {
    typealias Operation = @Sendable (_ delay: TimeInterval) async throws -> Void

    let operation: Operation

    static let live = AppAsyncSleep { delay in
        let delayNanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }

    func callAsFunction(for delay: TimeInterval) async throws {
        try await operation(delay)
    }
}

struct DebouncedTaskScheduler {
    typealias Action = @MainActor () async -> Void

    private let sleep: AppAsyncSleep

    init(sleep: AppAsyncSleep = .live) {
        self.sleep = sleep
    }

    func schedule(
        after delay: TimeInterval,
        replacing task: Task<Void, Never>?,
        action: @escaping Action
    ) -> Task<Void, Never> {
        task?.cancel()

        return Task {
            do {
                try await sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await action()
        }
    }
}
