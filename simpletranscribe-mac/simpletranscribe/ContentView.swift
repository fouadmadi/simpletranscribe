import SwiftUI
import ApplicationServices

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var showCopiedAlert = false
    @State private var showModelManager = false
    @State private var showHistory = false

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
                recordingElapsedSeconds: appModel.recordingElapsedSeconds,
                timeLimitWarning: appModel.recordingTimeLimitWarning,
                onToggleRecording: { appModel.toggleRecording() },
                onShowModelManager: { showModelManager = true }
            )

            Divider()

            SettingsAreaView(
                selectedInputDevice: $appModel.selectedInputDevice,
                selectedModelID: $appModel.selectedModelID,
                selectedLanguage: $appModel.selectedLanguage,
                useSystemDefault: $appModel.useSystemDefault,
                hotKeyModifiers: $appModel.hotKeyModifiers,
                streamingEnabled: $appModel.streamingEnabled,
                postProcessorConfig: $appModel.postProcessorConfig,
                autoClearAfterPaste: $appModel.autoClearAfterPaste,
                transcriptFontSize: $appModel.transcriptFontSize,
                diagnosticLogging: $appModel.diagnosticLogging,
                availableInputDevices: appModel.availableInputDevices,
                downloadedModels: appModel.modelService.availableModels.filter { $0.isAvailable },
                activeComputeBackend: appModel.activeComputeBackend
            )

            if !appModel.deviceSwitchMessage.isEmpty {
                Text(appModel.deviceSwitchMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08))
                    .transition(.opacity)
                    .animation(.easeInOut, value: appModel.deviceSwitchMessage)
            }

            Divider()

            pasteFailedBanner

            HSplitView {
                VStack(spacing: 0) {
                    TranscriptResultsView(
                        transcribedText: $appModel.transcribedText,
                        showCopiedAlert: $showCopiedAlert,
                        liveTranscriptText: appModel.liveTranscriptText,
                        isRecording: appModel.isRecording,
                        fontSize: appModel.transcriptFontSize,
                        onCopy: copyToClipboard,
                        onExport: { format in appModel.exportCurrentTranscript(format: format) }
                    )
                    Divider()
                    TranscriptStatusBar(
                        text: appModel.transcribedText,
                        lastDuration: appModel.lastRecordingDuration
                    )
                }
                .frame(minWidth: 300)

                if showHistory {
                    TranscriptHistoryView()
                        .frame(minWidth: 220, maxWidth: 350)
                }
            }

            modelStatusBanner
            errorBanner
            accessibilityBanner
        }
        .frame(minWidth: 600, minHeight: 350)
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation { showHistory.toggle() }
                } label: {
                    Label("History", systemImage: showHistory ? "clock.fill" : "clock")
                }
                .help(showHistory ? "Hide history" : "Show history")
            }
        }
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
                    // Only reset selection if the chosen model is no longer available
                    // (e.g. it was deleted). Preserve explicit user choices otherwise.
                    if appModel.modelService.getModel(appModel.selectedModelID)?.isAvailable != true {
                        appModel.selectDefaultModel()
                    }
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
    private var pasteFailedBanner: some View {
        if !appModel.pasteFailedMessage.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "clipboard.fill")
                    .foregroundColor(.orange)
                Text(appModel.pasteFailedMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy Again") {
                    copyToClipboard()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut, value: appModel.pasteFailedMessage)
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

