import SwiftUI

struct OverviewView: View {
    @Binding var selection: String?

    var body: some View {
        ContentUnavailableView("Overview", systemImage: "gauge.with.dots.needle.67percent")
    }
}
