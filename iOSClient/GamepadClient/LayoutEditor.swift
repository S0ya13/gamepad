import SharedProtocol
import SwiftUI

/// Full-screen editor for a profile's controls and sticks: drag to move, drag the round handle to resize,
/// tap to select and set up. Positions snap to 1/40 of the screen so neighbours line up without gaps.
struct LayoutEditor: View {
    @Binding var profile: Profile
    let stickRadius: CGFloat
    let onDone: () -> Void
    @State private var selected: UUID?
    /// true: the left stick is selected, false: the right one.
    @State private var selectedStick: Bool?
    @State private var styling = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.onTapGesture { select(nil) }
                Rectangle().fill(.white.opacity(0.2))
                    .frame(width: 1, height: geo.size.height)
                    .offset(x: geo.size.width / 2)
                    .allowsHitTesting(false)
                Text("Empty space: sticks · tap a stick or button to set it up")
                    .font(.caption).foregroundStyle(.white.opacity(0.3))
                    .frame(width: geo.size.width)
                    .offset(y: geo.size.height * 0.45)
                    .allowsHitTesting(false)
                EditableStick(setup: $profile.leftStick, left: true, radius: stickRadius, canvas: geo.size,
                              selected: selectedStick == true) { select(nil, stick: true) }
                EditableStick(setup: $profile.rightStick, left: false, radius: stickRadius, canvas: geo.size,
                              selected: selectedStick == false) { select(nil, stick: false) }
                ForEach($profile.controls) { $placed in
                    EditableControl(placed: $placed, canvas: geo.size, selected: selected == placed.id) {
                        select(placed.id)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { toolbar.padding(.bottom, 8) }
        .sheet(isPresented: $styling) {
            if let index = profile.controls.firstIndex(where: { $0.id == selected }) {
                ButtonSetup(placed: $profile.controls[index]) { styling = false }
                    .preferredColorScheme(.dark)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu("Add", systemImage: "plus") {
                ForEach(Control.allCases, id: \.self) { control in
                    Button(control.title) { add(control) }
                }
            }
            if let index = profile.controls.firstIndex(where: { $0.id == selected }) {
                Menu("Change", systemImage: "arrow.triangle.2.circlepath") {
                    ForEach(Control.allCases, id: \.self) { control in
                        Button(control.title) { profile.controls[index].control = control }
                    }
                }
                Button("Style", systemImage: "paintpalette") { styling = true }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    profile.controls.remove(at: index)
                    selected = nil
                }
            }
            if let left = selectedStick {
                Picker("Stick", selection: left ? $profile.leftStick.mode : $profile.rightStick.mode) {
                    ForEach(Profile.StickSetup.Mode.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            Menu("Start over", systemImage: "arrow.counterclockwise") {
                Button("Controller layout") { reset(to: .controller) }
                Button("Standard layout") { reset(to: .standard) }
                Button("Racing layout") { reset(to: .racing) }
            }
            Button("Done", action: onDone).bold()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private func select(_ id: UUID?, stick: Bool? = nil) {
        selected = id
        selectedStick = stick
    }

    private func reset(to preset: Profile) {
        profile.controls = preset.controls
        profile.leftStick = preset.leftStick
        profile.rightStick = preset.rightStick
        select(nil)
    }

    private func add(_ control: Control) {
        let placed = Profile.Placed(control: control, frame: CGRect(x: 0.425, y: 0.4, width: 0.15, height: 0.2))
        profile.controls.append(placed)
        select(placed.id)
    }
}

extension Profile.StickSetup.Mode {
    var title: String {
        switch self {
        case .fixed: "Fixed"
        case .floating: "Floating"
        case .dynamic: "Follows finger"
        }
    }
}

private extension Profile.Placed.Shape {
    var title: String {
        switch self {
        case .square: "Square"
        case .rounded: "Rounded"
        case .circle: "Circle"
        }
    }

    func outline(width: CGFloat, height: CGFloat) -> AnyShape {
        switch self {
        case .square: AnyShape(Rectangle())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: min(width, height) * 0.25))
        case .circle: AnyShape(Circle())
        }
    }
}

/// A stick's resting spot: drag it within its half; the toolbar sets how its base moves.
private struct EditableStick: View {
    @Binding var setup: Profile.StickSetup
    let left: Bool
    let radius: CGFloat
    let canvas: CGSize
    let selected: Bool
    let onSelect: () -> Void
    @State private var start: CGPoint?

    var body: some View {
        let c = CGPoint(x: setup.center.x * canvas.width, y: setup.center.y * canvas.height)
        let tint = selected ? Color.accentColor : .white.opacity(0.5)
        ZStack {
            Circle().fill(tint.opacity(0.12))
            Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: [6, 4]))
            VStack(spacing: 2) {
                Text(left ? "Left stick" : "Right stick").font(.caption.bold())
                Text(setup.mode.title).font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
        .onTapGesture(perform: onSelect)
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { drag in
                onSelect()
                let s = start ?? setup.center
                start = s
                let half: ClosedRange<CGFloat> = left ? 0...0.5 : 0.5...1
                setup.center = CGPoint(
                    x: min(max(s.x + drag.translation.width / canvas.width, half.lowerBound), half.upperBound),
                    y: min(max(s.y + drag.translation.height / canvas.height, 0), 1))
            }
            .onEnded { _ in start = nil })
        .position(c)
    }
}

private struct EditableControl: View {
    @Binding var placed: Profile.Placed
    let canvas: CGSize
    let selected: Bool
    let onSelect: () -> Void
    @State private var start: CGRect?

    var body: some View {
        let f = placed.frame
        let width = f.width * canvas.width, height = f.height * canvas.height
        let color = Color(uiColor: placed.uiColor)
        let outline = placed.shape.outline(width: width, height: height)
        ZStack(alignment: .bottomTrailing) {
            outline
                .fill(selected ? Color.accentColor.opacity(0.35) : color.opacity(0.1))
                .overlay(outline.stroke(selected ? Color.accentColor : color.opacity(0.5), lineWidth: selected ? 2 : 1))
                .overlay(Text(placed.title)
                    .font(.system(size: min(24, height * 0.4), weight: .semibold))
                    .foregroundStyle(color))
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                // Global space: the control moves under the finger, so its local space would shift mid-drag.
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { drag in
                        onSelect()
                        let s = start ?? f
                        start = s
                        placed.frame.origin = CGPoint(
                            x: snap(min(max(s.minX + drag.translation.width / canvas.width, 0), 1 - s.width)),
                            y: snap(min(max(s.minY + drag.translation.height / canvas.height, 0), 1 - s.height)))
                    }
                    .onEnded { _ in start = nil })
            if selected {
                Circle().fill(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .offset(x: 12, y: 12)
                    .accessibilityLabel("Resize")
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { drag in
                            let s = start ?? f
                            start = s
                            placed.frame.size = CGSize(
                                width: min(max(snap(s.width + drag.translation.width / canvas.width), 0.05), 1 - s.minX),
                                height: min(max(snap(s.height + drag.translation.height / canvas.height), 0.05), 1 - s.minY))
                        }
                        .onEnded { _ in start = nil })
            }
        }
        .frame(width: width, height: height)
        .offset(x: f.minX * canvas.width, y: f.minY * canvas.height)
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v * 40).rounded() / 40 }
}

/// One button's look and behaviour.
private struct ButtonSetup: View {
    @Binding var placed: Profile.Placed
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Label") {
                    TextField(placed.control.title, text: Binding(
                        get: { placed.label ?? "" },
                        set: { placed.label = $0.isEmpty ? nil : String($0.prefix(8)) }))
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
                Picker("Shape", selection: $placed.shape) {
                    ForEach(Profile.Placed.Shape.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                ColorPicker("Color", selection: Binding(
                    get: { Color(uiColor: placed.uiColor) },
                    set: { placed.color = UIColor($0).hex }), supportsOpacity: false)
                if placed.color != nil {
                    Button("Default colour") { placed.color = nil }
                }
                if placed.control.button != nil {
                    Section {
                        Toggle("Stays pressed", isOn: $placed.toggle)
                    } footer: {
                        Text("Tap once to hold the button down, tap again to let go. For sprint, crouch or aim held across a long run.")
                    }
                }
            }
            .navigationTitle(placed.control.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done", action: onDone) }
        }
    }
}
