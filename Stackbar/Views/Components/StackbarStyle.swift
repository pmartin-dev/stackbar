import SwiftUI

struct StatusDot: View {
  let color: Color
  var size: CGFloat = 8

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
  }
}

struct IconButton: View {
  let systemImage: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 28, height: 28)
    }
    .buttonStyle(HoverButtonStyle())
    .help(help)
  }
}

struct PlayStopButton: View {
  let isActive: Bool
  let isStopping: Bool
  let disabledReason: String?
  let size: CGFloat
  let stopHelp: String
  let launchHelp: String
  let stop: () -> Void
  let launch: () -> Void

  var body: some View {
    if isActive {
      Button(action: stop) {
        Image(systemName: "stop.fill")
      }
      .buttonStyle(PrimaryCircleButtonStyle(tint: .red, size: size))
      .help(isStopping ? "Retry stop" : stopHelp)
    } else {
      Button(action: launch) {
        Image(systemName: "play.fill")
      }
      .buttonStyle(PrimaryCircleButtonStyle(tint: .green, size: size))
      .disabled(disabledReason != nil)
      .help(disabledReason ?? launchHelp)
    }
  }
}

struct HoverButtonStyle: ButtonStyle {
  var padding: CGFloat = 0

  func makeBody(configuration: Configuration) -> some View {
    HoverButtonBody(configuration: configuration, padding: padding)
  }

  private struct HoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let padding: CGFloat
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .padding(padding)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.primary.opacity(configuration.isPressed ? 0.18 : isHovered ? 0.1 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovered = $0 && isEnabled }
        .pointerStyle(isEnabled ? .link : nil)
    }
  }
}

struct PrimaryCircleButtonStyle: ButtonStyle {
  let tint: Color
  var size: CGFloat = 30

  func makeBody(configuration: Configuration) -> some View {
    PrimaryCircleBody(configuration: configuration, tint: tint, size: size)
  }

  private struct PrimaryCircleBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let size: CGFloat
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .font(.system(size: size * 0.43, weight: .bold))
        .foregroundStyle(isEnabled ? (isHovered ? .white : tint) : .secondary)
        .frame(width: size, height: size)
        .background(
          Circle().fill(
            isEnabled
              ? tint.opacity(configuration.isPressed ? 0.75 : isHovered ? 0.9 : 0.18)
              : Color.primary.opacity(0.08)
          )
        )
        .contentShape(Circle())
        .scaleEffect(configuration.isPressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 && isEnabled }
        .pointerStyle(isEnabled ? .link : nil)
    }
  }
}

/// Rounded, tinted capsule button matching `PrimaryCircleButtonStyle`.
struct TintedButtonStyle: ButtonStyle {
  let tint: Color

  func makeBody(configuration: Configuration) -> some View {
    TintedButtonBody(configuration: configuration, tint: tint)
  }

  private struct TintedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(isEnabled ? (isHovered ? .white : tint) : .secondary)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous).fill(
            isEnabled
              ? tint.opacity(configuration.isPressed ? 0.75 : isHovered ? 0.9 : 0.18)
              : Color.primary.opacity(0.08)
          )
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 && isEnabled }
        .pointerStyle(isEnabled ? .link : nil)
    }
  }
}

/// Settings group: caption header above a softly tinted rounded card.
struct SettingsSection<Content: View, Accessory: View>: View {
  let title: String
  let accessory: Accessory
  let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
    self.title = title
    self.content = content()
    self.accessory = accessory()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        accessory
      }
      .padding(.horizontal, 4)
      .frame(minHeight: 28)

      VStack(alignment: .leading, spacing: 2) {
        content
      }
      .padding(6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.primary.opacity(0.04))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(.primary.opacity(0.06))
      )
    }
  }
}

/// Whole-row clickable switch with hover highlight.
struct SettingsToggleRow: View {
  let title: String
  var hint: String?
  @Binding var isOn: Bool
  @State private var isHovered = false

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
          if let hint {
            Text(hint)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        Toggle(title, isOn: $isOn)
          .toggleStyle(.switch)
          .controlSize(.small)
          .labelsHidden()
          .allowsHitTesting(false)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(.primary.opacity(isHovered ? 0.06 : 0))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
    }
  }
}

/// Plain text field chrome used in Settings.
struct FieldChrome: ViewModifier {
  var monospaced = false

  func body(content: Content) -> some View {
    content
      .textFieldStyle(.plain)
      .font(monospaced ? .body.monospaced() : .body)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(minHeight: 26)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(.primary.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(.primary.opacity(0.1))
      )
  }
}

extension View {
  func fieldChrome(monospaced: Bool = false) -> some View {
    modifier(FieldChrome(monospaced: monospaced))
  }
}

extension ProjectStatusSummary {
  var color: Color {
    switch status {
    case .running: errorMessage == nil ? .green : .orange
    case .partial: .yellow
    case .starting, .stopping: .orange
    case .failed: .red
    case .stopped: .gray.opacity(0.5)
    }
  }
}
