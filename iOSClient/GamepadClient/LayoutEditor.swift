import SharedProtocol
import SwiftUI

/// Full-screen editor for a profile's controls: drag to move, drag the round handle to resize.
/// Positions snap to 1/40 of the screen so neighbours line up without gaps.
struct LayoutEditor: View {
    @Binding var controls: [Profile.Placed]
    let onDone: () -> Void
    @State private var selected: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.onTapGesture { selected = nil }
                Rectangle().fill(.white.opacity(0.2))
                    .frame(width: 1, height: geo.size.height)
                    .offset(x: geo.size.width / 2)
                    .allowsHitTesting(false)
                Text("Empty space: left and right sticks")
                    .font(.caption).foregroundStyle(.white.opacity(0.3))
                    .frame(width: geo.size.width)
                    .offset(y: geo.size.height * 0.62)
                    .allowsHitTesting(false)
                ForEach($controls) { $placed in
                    EditableControl(placed: $placed, canvas: geo.size, selected: selected == placed.id) {
                        selected = placed.id
                    }
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { toolbar.padding(.bottom, 8) }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu("Add", systemImage: "plus") {
                ForEach(Control.allCases, id: \.self) { control in
                    Button(control.title) { add(control) }
                }
            }
            if let index = controls.firstIndex(where: { $0.id == selected }) {
                Menu("Change", systemImage: "arrow.triangle.2.circlepath") {
                    ForEach(Control.allCases, id: \.self) { control in
                        Button(control.title) { controls[index].control = control }
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    controls.remove(at: index)
                    selected = nil
                }
            }
            Menu("Start over", systemImage: "arrow.counterclockwise") {
                Button("Standard layout") { controls = Profile.standard.controls }
                Button("Racing layout") { controls = Profile.racing.controls }
            }
            Button("Done", action: onDone).bold()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private func add(_ control: Control) {
        let placed = Profile.Placed(control: control, frame: CGRect(x: 0.425, y: 0.4, width: 0.15, height: 0.2))
        controls.append(placed)
        selected = placed.id
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
        let height = f.height * canvas.height
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08))
                .overlay(Rectangle().strokeBorder(selected ? Color.accentColor : .white.opacity(0.4), lineWidth: selected ? 2 : 1))
                .overlay(Text(placed.control.title)
                    .font(.system(size: min(24, height * 0.4), weight: .semibold))
                    .foregroundStyle(.white))
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
        .frame(width: f.width * canvas.width, height: height)
        .offset(x: f.minX * canvas.width, y: f.minY * canvas.height)
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v * 40).rounded() / 40 }
}
