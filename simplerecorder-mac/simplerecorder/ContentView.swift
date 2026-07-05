import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            RecordingControlsView()
            Divider()
            RecordingsListView()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
