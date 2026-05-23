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
    static let pump300    = Color(hex: 0xF2A87B)
    static let caramel500 = Color(hex: 0xB98655)
    static let pr100      = Color(hex: 0xE2EED1)
    static let pr600      = Color(hex: 0x426524)
    static let skull600   = Color(hex: 0x8C2A1E)
    static let rpeLow     = Color(hex: 0xB0C170)
    static let rpeMid     = Color(hex: 0xE5B95C)
}

enum DZFont {
    static func display(size: CGFloat) -> Font {
        .custom("ArchivoBlack-Regular", size: size)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold: name = "JetBrainsMono-Bold"
        case .semibold, .medium: name = "JetBrainsMono-Medium"
        default: name = "JetBrainsMono-Regular"
        }
        return .custom(name, size: size)
    }
}

enum DZMetric {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32
    static let space10: CGFloat = 40
    static let space12: CGFloat = 48
    static let space16: CGFloat = 64

    static let radius: CGFloat = 14
    static let radiusSM: CGFloat = 10
    static let pillRadius: CGFloat = 999

    static let sectionSpacing: CGFloat = 18
    static let contentPadding: CGFloat = space4
    static let sectionHeaderPadding: CGFloat = space2
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = space3
    static let rowSpacing: CGFloat = space3
    static let infoTextSpacing: CGFloat = 3
    static let compactControlVerticalPadding: CGFloat = 10
    static let pillVerticalPadding: CGFloat = 7
    static let primaryButtonHorizontalPadding: CGFloat = 18
    static let templateCardPadding: CGFloat = 14
    static let rpeGap: CGFloat = 6
}

enum DZMotion {
    static let fastDuration: Double = 0.12
    static let pressScale: CGFloat = 0.97
    static let fastEaseOut = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: fastDuration)
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
            .dzShadowSM()
    }

    func dzShadowSM(isVisible: Bool = true) -> some View {
        shadow(color: DZColor.ink900.opacity(isVisible ? 0.04 : 0), radius: 0, x: 0, y: 1)
            .shadow(color: DZColor.ink900.opacity(isVisible ? 0.06 : 0), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    func dzNumeric(size: CGFloat? = nil, weight: Font.Weight = .semibold) -> some View {
        font(DZFont.mono(size: size ?? 17, weight: weight))
            .monospacedDigit()
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
        VStack(alignment: .leading, spacing: DZMetric.space2) {
            if let title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DZColor.ink700)
                    .textCase(.uppercase)
                    .padding(.horizontal, DZMetric.sectionHeaderPadding)
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
                    .padding(.horizontal, DZMetric.sectionHeaderPadding)
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
        HStack(alignment: .firstTextBaseline, spacing: DZMetric.rowSpacing) {
            VStack(alignment: .leading, spacing: DZMetric.infoTextSpacing) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(DZColor.ink900)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DZColor.ink700)
                }
            }

            Spacer(minLength: DZMetric.rowSpacing)

            if let value {
                Text(value)
                    .font(showsValueAsNumber ? .system(.body, design: .monospaced) : .body)
                    .monospacedDigit()
                    .foregroundStyle(DZColor.ink900)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, DZMetric.rowHorizontalPadding)
        .padding(.vertical, DZMetric.rowVerticalPadding)
    }
}

struct DZPressablePlainButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? DZMotion.pressScale : 1)
            .animation(DZMotion.fastEaseOut, value: configuration.isPressed)
    }
}

struct DZPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DZColor.fgOnPump)
            .padding(.vertical, DZMetric.rowVerticalPadding)
            .padding(.horizontal, DZMetric.primaryButtonHorizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(isEnabled ? DZColor.pump500 : DZColor.cream300)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.borderSoft, lineWidth: 1)
            )
            .dzShadowSM(isVisible: isEnabled)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? DZMotion.pressScale : 1)
            .animation(DZMotion.fastEaseOut, value: configuration.isPressed)
    }
}

struct DZSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DZColor.ink900)
            .padding(.vertical, DZMetric.compactControlVerticalPadding)
            .padding(.horizontal, DZMetric.rowHorizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(DZColor.cream100)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.sand400, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? DZMotion.pressScale : 1)
            .animation(DZMotion.fastEaseOut, value: configuration.isPressed)
    }
}

struct DZPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(DZColor.ink900)
            .padding(.vertical, DZMetric.pillVerticalPadding)
            .frame(maxWidth: .infinity)
            .background(DZColor.cream200)
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? DZMotion.pressScale : 1)
            .animation(DZMotion.fastEaseOut, value: configuration.isPressed)
    }
}

struct DZDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(DZColor.skull500)
            .padding(.vertical, DZMetric.compactControlVerticalPadding)
            .padding(.horizontal, DZMetric.rowHorizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(DZColor.skull100.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.skull500.opacity(0.16), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && isEnabled ? DZMotion.pressScale : 1)
            .animation(DZMotion.fastEaseOut, value: configuration.isPressed)
    }
}

struct DZTemplateCard: View {
    let name: String
    let exerciseCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DZMetric.space4) {
                Text(name)
                    .font(DZFont.display(size: 22))
                    .foregroundStyle(DZColor.ink900)
                    .textCase(.uppercase)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text("\(exerciseCount) 个动作")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentTextColor)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .bottomLeading)
            .padding(DZMetric.templateCardPadding)
            .background(accentBackground)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous)
                    .stroke(DZColor.borderSoft, lineWidth: 1)
            )
            .dzShadowSM()
        }
        .buttonStyle(DZPressablePlainButtonStyle())
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
        HStack(spacing: DZMetric.rpeGap) {
            ForEach(values, id: \.self) { rpe in
                Button {
                    selection = selection == rpe ? nil : rpe
                } label: {
                    Text("\(rpe)")
                        .dzNumeric(size: 16, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DZMetric.compactControlVerticalPadding)
                        .background(selection == rpe ? rpeFill(rpe) : DZColor.cream50)
                        .foregroundStyle(selection == rpe ? rpeFg(rpe) : DZColor.ink900)
                        .clipShape(RoundedRectangle(cornerRadius: DZMetric.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DZMetric.radiusSM, style: .continuous)
                                .stroke(DZColor.borderSoft, lineWidth: 1)
                        )
                }
                .buttonStyle(DZPressablePlainButtonStyle())
                .accessibilityIdentifier("rpe-\(rpe)")
            }
        }
    }

    private func rpeFill(_ rpe: Int) -> Color {
        switch rpe {
        case 6:     return DZColor.rpeLow
        case 7, 8:  return DZColor.rpeMid
        case 9:     return DZColor.pump500
        default:    return DZColor.skull500
        }
    }

    private func rpeFg(_ rpe: Int) -> Color {
        rpe <= 8 ? DZColor.ink900 : DZColor.fgOnPump
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
