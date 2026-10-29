import CoreGraphics

@main
struct MenuPanelLayoutBehavior {
    static func main() {
        expectEqual(
            MenuPanelLayout.historyListHeight(recordCount: 0, displayLimit: 20),
            0,
            "empty history should not reserve list height"
        )
        expectEqual(
            MenuPanelLayout.mainPanelHeight(recordCount: 0, displayLimit: 20),
            MenuPanelLayout.panelMinHeight,
            "empty history should use the minimum panel height"
        )

        let oneRecordHeight = MenuPanelLayout.mainPanelHeight(recordCount: 1, displayLimit: 20)
        let threeRecordHeight = MenuPanelLayout.mainPanelHeight(recordCount: 3, displayLimit: 20)
        expect(oneRecordHeight >= MenuPanelLayout.panelMinHeight, "records should never shrink below minimum")
        expect(threeRecordHeight > oneRecordHeight, "panel should grow as visible record count grows")
        expectEqual(
            MenuPanelLayout.historyListHeight(recordCount: 5, displayLimit: 20),
            MenuPanelLayout.historyRowHeight * 5,
            "five visible records should fit without artificial bottom blank space"
        )
        expect(
            MenuPanelLayout.historyListHeight(recordCount: 6, displayLimit: 20) <
                MenuPanelLayout.historyRowHeight * 6,
            "six visible records should scroll before bottom actions are clipped"
        )

        expectEqual(
            MenuPanelLayout.mainPanelHeight(recordCount: 50, displayLimit: 20),
            MenuPanelLayout.panelMaxHeight,
            "large histories should clamp to maximum panel height"
        )
        expectEqual(
            MenuPanelLayout.historyListHeight(recordCount: 50, displayLimit: 2),
            MenuPanelLayout.historyRowHeight * 2,
            "display limit should cap the dynamic list height"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    private static func expectEqual(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        precondition(abs(actual - expected) < 0.001, "\(message): expected \(expected), got \(actual)")
    }
}
