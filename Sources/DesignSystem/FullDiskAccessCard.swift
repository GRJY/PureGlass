import SwiftUI
import AppKit
import PureGlassKit

/// Full Disk Access durumunu canlı gösteren ve izin akışını yöneten glass kart.
/// İzin verildiğinde polling sayesinde otomatik olarak güncellenir.
struct FullDiskAccessCard: View {
    let coordinator: PermissionCoordinator

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                HStack {
                    Label(L("Tam Disk Erişimi", "Full Disk Access"), systemImage: "lock.shield")
                        .font(.dsTitle)
                    Spacer()
                    statusBadge
                }

                Text(L("Derin temizlik için PureGlass'in korumalı klasörleri okuması gerekir. İzin Sistem Ayarları'ndan elle verilir; verilerin cihazından çıkmaz.", "Deep clean needs PureGlass to read protected folders. You grant the permission manually in System Settings; your data never leaves the device."))
                    .font(.iCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !coordinator.isGranted {
                    HStack(spacing: DS.Spacing.m) {
                        Button { openSettings() } label: {
                            Label(L("Ayarları Aç", "Open Settings"), systemImage: "arrow.up.forward.app")
                                .padding(.horizontal, DS.Spacing.s)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.accentColor)

                        Button { coordinator.refresh() } label: {
                            Label("Yeniden Denetle", systemImage: "arrow.clockwise")
                                .padding(.horizontal, DS.Spacing.s)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { coordinator.startPolling() }
        .onDisappear { coordinator.stopPolling() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Label(statusTitle, systemImage: statusIcon)
            .font(.iCaption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, DS.Spacing.s)
            .padding(.vertical, DS.Spacing.xs)
            .glassEffect(.regular.tint(statusColor.opacity(0.30)), in: .capsule)
    }

    private var statusTitle: String {
        switch coordinator.status {
        case .granted: "Verildi"
        case .denied: "Verilmedi"
        case .unknown: "Bilinmiyor"
        }
    }

    private var statusIcon: String {
        switch coordinator.status {
        case .granted: "checkmark.seal.fill"
        case .denied: "xmark.seal.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .granted: DS.Palette.safe
        case .denied: DS.Palette.danger
        case .unknown: DS.Palette.caution
        }
    }

    private func openSettings() {
        NSWorkspace.shared.open(coordinator.settingsURL)
        coordinator.startPolling()
    }
}
