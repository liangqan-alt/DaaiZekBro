import SwiftUI

enum DZColor {
    static let cream50 = Color(hex: 0xFBF5E9)
    static let cream100 = Color(hex: 0xF8E9D8)
    static let cream200 = Color(hex: 0xF5E0C4)
    static let cream300 = Color(hex: 0xEDD2A9)
    static let sand400 = Color(hex: 0xE0BB88)
    static let caramel400 = Color(hex: 0xD0A26D)
    static let bronze600 = Color(hex: 0x8B6638)
    static let bronze700 = Color(hex: 0x6E4F2A)
    static let ink900 = Color(hex: 0x1F1810)
    static let ink800 = Color(hex: 0x2E261C)
    static let ink700 = Color(hex: 0x4A3F30)
    static let pump100 = Color(hex: 0xFCE3D2)
    static let pump500 = Color(hex: 0xD86838)
    static let pump600 = Color(hex: 0xB6512A)
    static let pr500 = Color(hex: 0x5C8A3A)
    static let skull500 = Color(hex: 0xB23A2A)
    static let skull100 = Color(hex: 0xF5D6CF)
    static let fgOnPump = Color(hex: 0xFFFCF6)
    static let borderSoft = ink900.opacity(0.08)
    static let fgFaint = ink900.opacity(0.45)
}

enum DZMetric {
    static let radius: CGFloat = 14
    static let pillRadius: CGFloat = 999
    static let sectionSpacing: CGFloat = 18
    static let contentPadding: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex & 0xFF0000) >> 16) / 255
        let green = Double((hex & 0x00FF00) >> 8) / 255
        let blue = Double(hex & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension View {
    func dzScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(DZColor.cream50.ignoresSafeArea())
    }

    func dzCardStyle(cornerRadius: CGFloat = DZMetric.radius) -> some View {
        background(DZColor.cream100)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DZColor.borderSoft, lineWidth: 1)
            )
            .shadow(color: DZColor.ink900.opacity(0.06), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func dzNumeric(size: CGFloat? = nil, weight: Font.Weight = .semibold) -> some View {
        if let size {
            font(.system(size: size, weight: weight, design: .monospaced))
                .monospacedDigit()
        } else {
            font(.system(.body, design: .monospaced).weight(weight))
                .monospacedDigit()
        }
    }
}

struct DZSection<Content: View>: View {
    let title: String?
    let footer: String?
    private let content: Content

    init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DZColor.ink700)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dzCardStyle()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
            }
        }
    }
}

struct DZDivider: View {
    var body: some View {
        Divider()
            .overlay(DZColor.borderSoft)
    }
}

struct DZInfoRow: View {
    let title: String
    let value: String?
    var subtitle: String?
    var showsValueAsNumber = false

    init(
        _ title: String,
        value: String? = nil,
        subtitle: String? = nil,
        showsValueAsNumber: Bool = false
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.showsValueAsNumber = showsValueAsNumber
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(DZColor.ink900)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DZColor.ink700)
                }
            }

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .font(showsValueAsNumber ? .system(.body, design: .monospaced) : .body)
                    .monospacedDigit()
                    .foregroundStyle(DZColor.ink900)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct DZPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DZColor.fgOnPump)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(isEnabled ? DZColor.pump500 : DZColor.cream300)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.borderSoft, lineWidth: 1)
            )
            .shadow(color: DZColor.ink900.opacity(isEnabled ? 0.08 : 0), radius: 8, x: 0, y: 4)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DZSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DZColor.ink900)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(DZColor.cream100)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.sand400, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DZPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(DZColor.ink900)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(DZColor.cream200)
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DZDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DZColor.skull500)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(DZColor.skull100.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.skull500.opacity(0.16), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DZTemplateCard: View {
    let name: String
    let exerciseCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Text(name)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DZColor.ink900)
                    .textCase(.uppercase)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text("\(exerciseCount) 个动作")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentTextColor)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .bottomLeading)
            .padding(14)
            .background(accentBackground)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.borderSoft, lineWidth: 1)
            )
            .shadow(color: DZColor.ink900.opacity(0.06), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var accentBackground: Color {
        if name.hasPrefix("Legs") {
            return Color(hex: 0xE8C896)
        }

        if name.hasPrefix("Pull") {
            return Color(hex: 0xEAD8B4)
        }

        return DZColor.cream200
    }

    private var accentTextColor: Color {
        if name.hasPrefix("Legs") {
            return Color(hex: 0x5A3D1A)
        }

        if name.hasPrefix("Pull") {
            return DZColor.bronze700
        }

        return DZColor.bronze600
    }
}

struct DZRPEPicker: View {
    let values: [Int]
    @Binding var selection: Int?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { rpe in
                Button {
                    selection = selection == rpe ? nil : rpe
                } label: {
                    Text("\(rpe)")
                        .dzNumeric(size: 16, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selection == rpe ? DZColor.pump500 : DZColor.cream50)
                        .foregroundStyle(selection == rpe ? DZColor.fgOnPump : DZColor.ink900)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DZColor.borderSoft, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rpe-\(rpe)")
            }
        }
    }
}

struct DZLoggedSetBadge: View {
    let index: Int

    var body: some View {
        Text("\(index)")
            .dzNumeric(size: 11, weight: .bold)
            .foregroundStyle(DZColor.pump600)
            .frame(width: 24, height: 24)
            .background(DZColor.pump100)
            .clipShape(Circle())
    }
}
