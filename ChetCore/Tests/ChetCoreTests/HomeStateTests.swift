import Testing

@testable import ChetCore

@Suite struct HomeStateTests {
    private func resolve(
        isScanning: Bool = false,
        hasScanned: Bool = true,
        didFinishScan: Bool = true,
        totalBytes: Int64 = 0,
        blockingReadErrorCount: Int = 0,
        needsFullDiskAccess: Bool = false
    ) -> HomeState {
        HomeState.resolve(
            isScanning: isScanning,
            hasScanned: hasScanned,
            didFinishScan: didFinishScan,
            totalBytes: totalBytes,
            blockingReadErrorCount: blockingReadErrorCount,
            needsFullDiskAccess: needsFullDiskAccess)
    }

    @Test func scanningWithBytesStillScans() {
        #expect(resolve(isScanning: true, totalBytes: 42) == .scanning)
    }

    @Test func scanningWinsOverNeverScanned() {
        #expect(resolve(isScanning: true, hasScanned: false) == .scanning)
    }

    @Test func neverScannedWinsOverUnreadableSignals() {
        #expect(
            resolve(hasScanned: false, blockingReadErrorCount: 3, needsFullDiskAccess: true)
                == .neverScanned)
    }

    @Test func previousScanWithoutAFinishedScanIsNotTidy() {
        let state = resolve(didFinishScan: false, totalBytes: 0)
        #expect(state == .unreadable)
        #expect(state != .measuredEmpty)
    }

    @Test func readErrorWithNoBytesIsUnreadable() {
        #expect(resolve(totalBytes: 0, blockingReadErrorCount: 1) == .unreadable)
    }

    @Test func missingFullDiskAccessWithNoBytesIsUnreadable() {
        #expect(resolve(totalBytes: 0, needsFullDiskAccess: true) == .unreadable)
    }

    @Test func cleanFinishedScanWithNoBytesIsMeasuredEmpty() {
        #expect(resolve(totalBytes: 0) == .measuredEmpty)
    }

    @Test func finishedScanWithBytesHasFindings() {
        #expect(resolve(totalBytes: 1) == .hasFindings)
    }

    @Test func copyNamesEveryReason() {
        #expect(HomeState.scanning.subtitle == "Scanning. Results appear as they finish.")
        #expect(HomeState.scanning.emptyTitle == nil)
        #expect(HomeState.scanning.emptyMessage == nil)

        #expect(HomeState.neverScanned.subtitle == "A clear account of this disk.")
        #expect(HomeState.neverScanned.emptyTitle == nil)
        #expect(HomeState.neverScanned.emptyMessage == nil)

        #expect(HomeState.unreadable.subtitle == "Chet could not read every folder.")
        #expect(HomeState.unreadable.emptyTitle == "Not everything was read")
        #expect(
            HomeState.unreadable.emptyMessage
                == "Grant Full Disk Access to include caches, app data, and Mail downloads.")

        #expect(HomeState.measuredEmpty.subtitle == "This Mac is tidy.")
        #expect(HomeState.measuredEmpty.emptyTitle == "Nothing to reclaim")
        #expect(HomeState.measuredEmpty.emptyMessage == "This Mac is tidy.")

        #expect(HomeState.hasFindings.subtitle == nil)
        #expect(HomeState.hasFindings.emptyTitle == nil)
        #expect(HomeState.hasFindings.emptyMessage == nil)
    }
}
