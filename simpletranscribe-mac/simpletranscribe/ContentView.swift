import SwiftUI
import ApplicationServices

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var showCopiedAlert = false
    @State private var showModelManager = false

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 0) {
            RecordingControlsView(
                isRecording: appModel.isRecording,
                isProcessing: appModel.isProcessing,
                isTranscribing: appModel.isTranscribing,
                canRecord: appModel.canRecord,
                isLoadingModel: appModel.isLoadingModel,
                showTranscriptionStarted: appModel.showTranscriptionStarted,
                onToggleRecording: { appModel.toggleRecording() },
                onShowModelManager: { showModelManager = true }
            )

            Divider()

            SettingsAreaView(
                selectedInputDevice: $appModel.selectedInputDevice,
                selectedModelID: $appModel.selectedModelID,
                selectedLanguage: $appModel.selectedLanguage,
                availableInputDevices: appModel.availableInputDevices,
                downloadedModels: appModel.modelService.availableModels.filter { $0.isAvailable }
            )

            Divider()

            TranscriptResultsView(
                transcribedText: $appModel.transcribedText,
                showCopiedAlert: $showCopiedAlert,
                onCopy: copyToClipboard
            )

            modelStatusBanner
            errorBanner
            accessibilityBanner
        }
        .frame(minWidth: 600, minHeight: 350)
        .onChange(of: appModel.selectedModelID) { oldValue, newValue in
            appModel.modelLoaded = false
            appModel.errorMessage = nil
            if !newValue.isEmpty,
               appModel.modelService.getModel(newValue)?.isAvailable == true {
                appModel.loadModel()
            }
        }
        .sheet(isPresented: $showModelManager) {
            ModelDownloadView(appModel: appModel)
                .frame(minWidth: 700, minHeight: 350)
                .onDisappear {
                    appModel.selectDefaultModel()
                }
        }
    }

    // MARK: - Status Banners

    @ViewBuilder
    private var modelStatusBanner: some View {
        if appModel.isLoadingModel {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.1))
        } else if !appModel.modelLoaded && appModel.hasDownloadedModels {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.accentColor)
                Text("Model not loaded. Click to load manually.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Load Model") {
                    appModel.loadModel()
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .disabled(appModel.selectedModelID.isEmpty)
            }
            .padding()
            .background(Color.accentColor.opacity(0.08))
        } else if !appModel.modelLoaded {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text("No models downloaded. Download a model to get started.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Download") {
                    showModelManager = true
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = appModel.errorMessage {
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var accessibilityBanner: some View {
        if !appModel.accessibilityGranted {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Accessibility permission needed for paste-at-cursor")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                }
                Text("In Settings → Accessibility, click + and add this app.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Clipboard

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appModel.transcribedText, forType: .string)

        showCopiedAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedAlert = false
        }
    }
}

