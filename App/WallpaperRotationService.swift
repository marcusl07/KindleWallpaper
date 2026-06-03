import Dispatch
import Foundation

private let wallpaperRotationQueue = DispatchQueue(
    label: "KindleWall.AppState.WallpaperRotation",
    qos: .userInitiated
)

enum WallpaperRotationService {
    struct Context {
        let selectHighlight: () -> Highlight?
        let loadBackgroundImageURLs: AppState.LoadBackgroundImageURLs
        let selectBackgroundImageURL: AppState.SelectBackgroundImageURL
        let capitalizeFirstLetterIfLowercase: Bool
        let generateWallpaper: AppState.GenerateWallpaper
        let setWallpaper: AppState.SetWallpaper
        let prepareWallpaperRotation: AppState.PrepareWallpaperRotation?
        let generateWallpapers: AppState.GenerateWallpapers?
        let persistAppliedWallpaperAssignments: ([AppState.GeneratedWallpaper]) -> Void
        let retryWallpaperAssignmentMigrationIfNeeded: AppState.RetryWallpaperAssignmentMigrationIfNeeded
        let markHighlightShown: AppState.MarkHighlightShown
        let setLastChangedAt: (Date) -> Void
        let now: AppState.Now
    }

    struct Execution {
        let outcome: AppState.WallpaperRotationOutcome
        let currentQuotePreview: String?
        let lastChangedAt: Date?
    }

    static func enqueue(_ work: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: work)
        wallpaperRotationQueue.async(execute: workItem)
    }

    static func deliverOnMain(_ work: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: work)
        DispatchQueue.main.async(execute: workItem)
    }

    static func run(using context: Context) -> Execution {
        guard let highlight = context.selectHighlight() else {
            return Execution(
                outcome: .noActivePool,
                currentQuotePreview: nil,
                lastChangedAt: nil
            )
        }

        let displayQuoteText = transformedQuoteTextForDisplay(
            highlight.quoteText,
            capitalizeFirstLetterIfLowercase: context.capitalizeFirstLetterIfLowercase
        )
        let highlightForDisplay = displayHighlight(highlight, quoteText: displayQuoteText)
        let backgroundURL = context.selectBackgroundImageURL(context.loadBackgroundImageURLs())
        let appliedGeneratedWallpapers: [AppState.GeneratedWallpaper]
        if
            let prepareWallpaperRotation = context.prepareWallpaperRotation,
            let generateWallpapers = context.generateWallpapers,
            let rotationPlan = prepareWallpaperRotation()
        {
            let targets = rotationPlan.targets
            guard !targets.isEmpty else {
                return Execution(
                    outcome: .wallpaperApplyFailure(.noTargets),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }

            let generatedWallpapers: [AppState.GeneratedWallpaper]
            do {
                generatedWallpapers = try generateWallpapers(highlightForDisplay, backgroundURL, targets)
            } catch {
                return Execution(
                    outcome: .wallpaperApplyFailure(.applyError),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }

            let targetIdentifiers = Set(targets.map { $0.identifier })
            let generatedIdentifiers = Set(generatedWallpapers.map { $0.targetIdentifier })

            guard
                generatedWallpapers.count == targets.count,
                generatedIdentifiers == targetIdentifiers
            else {
                return Execution(
                    outcome: .wallpaperApplyFailure(.generatedTargetMismatch),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }

            do {
                try rotationPlan.apply(generatedWallpapers)
            } catch {
                return Execution(
                    outcome: .wallpaperApplyFailure(.applyError),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }

            appliedGeneratedWallpapers = generatedWallpapers
        } else {
            do {
                let wallpaperURL = try context.generateWallpaper(highlightForDisplay, backgroundURL)
                try context.setWallpaper(wallpaperURL)
                appliedGeneratedWallpapers = [
                    AppState.GeneratedWallpaper(
                        targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                        fileURL: wallpaperURL
                    )
                ]
            } catch {
                return Execution(
                    outcome: .wallpaperApplyFailure(.applyError),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }
        }

        context.persistAppliedWallpaperAssignments(appliedGeneratedWallpapers)
        context.retryWallpaperAssignmentMigrationIfNeeded()
        context.markHighlightShown(highlight.id)
        let changedAt = context.now()
        context.setLastChangedAt(changedAt)
        return Execution(
            outcome: .success,
            currentQuotePreview: displayQuoteText,
            lastChangedAt: changedAt
        )
    }

    private static func displayHighlight(_ highlight: Highlight, quoteText: String) -> Highlight {
        Highlight(
            id: highlight.id,
            bookId: highlight.bookId,
            quoteText: quoteText,
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            dateAdded: highlight.dateAdded,
            lastShownAt: highlight.lastShownAt,
            isEnabled: highlight.isEnabled
        )
    }

    private static func transformedQuoteTextForDisplay(
        _ quoteText: String,
        capitalizeFirstLetterIfLowercase: Bool
    ) -> String {
        guard capitalizeFirstLetterIfLowercase else {
            return quoteText
        }

        guard let firstLetterRange = firstLetterRange(in: quoteText) else {
            return quoteText
        }

        let firstLetter = quoteText[firstLetterRange]
        let firstLetterString = String(firstLetter)
        let lowercase = firstLetterString.lowercased()
        let uppercase = firstLetterString.uppercased()

        guard firstLetterString == lowercase, firstLetterString != uppercase else {
            return quoteText
        }

        var transformed = quoteText
        transformed.replaceSubrange(firstLetterRange, with: uppercase)
        return transformed
    }

    private static func firstLetterRange(in text: String) -> Range<String.Index>? {
        for index in text.indices {
            let nextIndex = text.index(after: index)
            let characterRange = index..<nextIndex
            let character = String(text[characterRange])
            if character.rangeOfCharacter(from: .letters) != nil {
                return characterRange
            }
        }
        return nil
    }
}
