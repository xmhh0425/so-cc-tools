import CoreGraphics

enum MenuPanelLayout {
    static let panelWidth: CGFloat = 340
    static let panelMinHeight: CGFloat = 260
    static let panelMaxHeight: CGFloat = 560
    static let historyRowHeight: CGFloat = 66

    private static let headerAndStatusHeight: CGFloat = 68
    private static let separatorsHeight: CGFloat = 3
    private static let actionSectionHeightWithHistory: CGFloat = 95
    private static let mainChromeHeightWithHistory =
        headerAndStatusHeight + separatorsHeight + actionSectionHeightWithHistory
    private static var maxHistoryListHeight: CGFloat {
        panelMaxHeight - mainChromeHeightWithHistory
    }

    static func historyListHeight(recordCount: Int, displayLimit: Int) -> CGFloat {
        let visibleCount = visibleHistoryCount(recordCount: recordCount, displayLimit: displayLimit)
        guard visibleCount > 0 else { return 0 }

        return min(CGFloat(visibleCount) * historyRowHeight, maxHistoryListHeight)
    }

    static func mainPanelHeight(recordCount: Int, displayLimit: Int) -> CGFloat {
        let visibleCount = visibleHistoryCount(recordCount: recordCount, displayLimit: displayLimit)
        guard visibleCount > 0 else { return panelMinHeight }

        let contentHeight = mainChromeHeightWithHistory + historyListHeight(
            recordCount: recordCount,
            displayLimit: displayLimit
        )
        return min(panelMaxHeight, max(panelMinHeight, contentHeight))
    }

    private static func visibleHistoryCount(recordCount: Int, displayLimit: Int) -> Int {
        min(max(recordCount, 0), max(displayLimit, 0))
    }
}
