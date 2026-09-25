#if os(iOS)
import SwiftUI
import UIKit

/// The system persists this choice independently of Graphite's vaults and accent color.
private enum AppIconOption: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case red = "Red"
    case black = "Black"
    case charcoal = "Charcoal"
    case blueGraphite = "BlueGraphite"

    var id: String { rawValue }
    var title: String { self == .blueGraphite ? "Blue graphite" : rawValue }
    var alternateIconName: String? { self == .blue ? nil : "AppIcon" + rawValue }
    var previewName: String { "AppIconPreview" + rawValue }
}

struct AppIconSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var pendingOption: AppIconOption?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if UIApplication.shared.supportsAlternateIcons {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                    ForEach(AppIconOption.allCases) { option in
                        let isSelected = selectedIconName == option.alternateIconName
                        Button {
                            Task { await changeIcon(to: option) }
                        } label: {
                            VStack(spacing: 8) {
                                Image(option.previewName, bundle: .main)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(5)
                                    .frame(width: 88, height: 88)
                                    .background(LinearGradient(
                                        colors: [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.84, green: 0.89, blue: 0.94)],
                                        startPoint: .top, endPoint: .bottom
                                    ), in: RoundedRectangle(cornerRadius: 20))
                                    .overlay(alignment: .bottomTrailing) {
                                        if pendingOption == option {
                                            ProgressView().padding(5).background(.regularMaterial, in: Circle())
                                        } else if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Color.accentColor)
                                                .font(.title3)
                                        }
                                    }
                                Text(option.title).font(.caption).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(pendingOption != nil)
                        .accessibilityLabel(option.title + " app icon")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Changing the app icon is unavailable on this device.").foregroundStyle(.secondary)
            }
        } header: {
            Text("App icon")
        } footer: {
            Text("Choose matching ink and pencil-tip colors for your Home Screen icon. Blue is the default. Your notes and accent color stay the same.")
        }
        .onAppear { selectedIconName = UIApplication.shared.alternateIconName }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { selectedIconName = UIApplication.shared.alternateIconName }
        }
        .alert("Couldn’t Change App Icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @MainActor private func changeIcon(to option: AppIconOption) async {
        guard pendingOption == nil, UIApplication.shared.alternateIconName != option.alternateIconName else { return }
        pendingOption = option
        defer {
            selectedIconName = UIApplication.shared.alternateIconName
            pendingOption = nil
        }
        do {
            try await UIApplication.shared.setAlternateIconName(option.alternateIconName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
