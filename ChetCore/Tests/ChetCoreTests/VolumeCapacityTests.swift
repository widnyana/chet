import Testing

@testable import ChetCore

struct VolumeCapacityTests {
    @Test func purgeableIsImportantMinusRawFreeClamped() {
        let withPurgeable = VolumeCapacity.make(name: "Disk", total: 1000, rawFree: 100, importantFree: 150)
        #expect(withPurgeable.free == 100)
        #expect(withPurgeable.purgeable == 50)

        let none = VolumeCapacity.make(name: "Disk", total: 1000, rawFree: 200, importantFree: 150)
        #expect(none.purgeable == 0)
    }
}
