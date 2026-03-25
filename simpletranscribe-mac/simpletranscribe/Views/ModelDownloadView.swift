import SwiftUI

struct ModelDownloadView: View {
    @Bindable var appModel: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var showingDetails = false
    @State private var selectedModelDetails: ModelInfo?
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription Models")
                        .font(.headline)
                    Text("Select or download a model to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Storage info
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.secondary)
                Text("Storage Used: \(formatBytes(appModel.modelService.totalDownloadedSize()))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            // Model list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(appModel.modelService.availableModels) { model in
                        ModelRowView(
                            model: model,
                            modelService: appModel.modelService,
                            isSelected: appModel.selectedModelID == model.id,
                            onDownload: {
                                Task {
                                    try await appModel.modelService.downloadModel(model.id)
                                }
                            },
                            onDelete: {
                                try? appModel.modelService.deleteModel(model.id)
                            },
                            onSelect: {
                                appModel.selectedModelID = model.id
                            }
                        )
                    }
                }
                .padding()
            }
            
            Spacer()
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ModelRowView: View {
    let model: ModelInfo
    let modelService: ModelService
    let isSelected: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Status indicator & selection
                VStack(spacing: 8) {
                    if isSelected && model.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    } else if model.isAvailable {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                            .font(.title3)
                    } else if model.status == .downloading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
                
                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.body)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        Text(model.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if model.language != "unknown" {
                            Label(model.language.uppercased(), systemImage: "globe")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 8) {
                    if model.isAvailable {
                        Button(action: onSelect) {
                            if isSelected {
                                Text("Selected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Select")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSelected)
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                        .help("Delete model")
                    } else if model.status == .downloading {
                        Button(action: {
                            modelService.cancelDownload(model.id)
                        }) {
                            Text("Cancel")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: onDownload) {
                            Image(systemName: "icloud.and.arrow.down")
                            Text("Download")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // Download progress
            if model.status == .downloading,
               let progress = modelService.downloadProgress[model.id] {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Error message with retry
            if model.status == .failed,
               let error = modelService.downloadError[model.id] {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button(action: {
                        modelService.downloadError.removeValue(forKey: model.id)
                        onDownload()
                    }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    ModelDownloadView(appModel: AppModel())
        .frame(width: 600, height: 400)
}
