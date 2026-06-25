import SwiftUI

/// Özet istatistik kutucuğu (örn. L("Kazanılacak alan: 12,4 GB", "Space to gain: 12.4 GB")).
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String
    var tint: Color = DS.Palette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Label(title, systemImage: systemImage)
                .font(.iCaption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.dsDisplay(30))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.m))
    }
}
