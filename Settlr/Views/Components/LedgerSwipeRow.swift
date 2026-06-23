import SwiftUI

struct LedgerSwipeRow<Content: View>: View {
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var revealed: RevealedSide?
    @GestureState private var dragTranslation: CGFloat = 0

    private enum RevealedSide {
        case delete
        case edit
    }

    private let actionWidth: CGFloat = 96
    private let openThreshold: CGFloat = 48

    private var spring: Animation {
        .interactiveSpring(response: 0.32, dampingFraction: 0.88, blendDuration: 0.1)
    }

    private var offset: CGFloat {
        rubberBand(baseOffset(for: revealed) + dragTranslation)
    }

    private var editRevealWidth: CGFloat { max(0, offset) }
    private var deleteRevealWidth: CGFloat { max(0, -offset) }

    private var isOpen: Bool {
        revealed != nil || abs(dragTranslation) > 0.5
    }

    var body: some View {
        ZStack(alignment: .leading) {
            content()
                .offset(x: offset)
                .onTapGesture {
                    if isOpen {
                        close()
                    } else {
                        onTap()
                    }
                }

            actionOverlay
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var actionOverlay: some View {
        HStack(spacing: 0) {
            actionButton(
                title: "Edit",
                systemImage: "pencil",
                background: Color(hex: "#c8ff5a"),
                foreground: Color(hex: "#0e0f11"),
                revealWidth: editRevealWidth,
                alignment: .leading,
                action: {
                    close()
                    onEdit()
                }
            )

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            actionButton(
                title: "Delete",
                systemImage: "trash.fill",
                background: Color(hex: "#e54848"),
                foreground: .white,
                revealWidth: deleteRevealWidth,
                alignment: .trailing,
                action: {
                    close()
                    onDelete()
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard isHorizontalDrag(value.translation) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isHorizontalDrag(value.translation) else { return }

                let projected = baseOffset(for: revealed) + value.translation.width
                withAnimation(spring) {
                    if projected > openThreshold {
                        revealed = .edit
                    } else if projected < -openThreshold {
                        revealed = .delete
                    } else {
                        revealed = nil
                    }
                }
            }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        background: Color,
        foreground: Color,
        revealWidth: CGFloat,
        alignment: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                background
                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(foreground)
            }
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: revealWidth, alignment: alignment)
        .frame(maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(revealWidth > 28)
    }

    private func close() {
        withAnimation(spring) {
            revealed = nil
        }
    }

    private func baseOffset(for side: RevealedSide?) -> CGFloat {
        switch side {
        case nil: 0
        case .edit: actionWidth
        case .delete: -actionWidth
        }
    }

    private func rubberBand(_ value: CGFloat) -> CGFloat {
        if value > actionWidth {
            return actionWidth + (value - actionWidth) * 0.18
        }
        if value < -actionWidth {
            return -actionWidth + (value + actionWidth) * 0.18
        }
        return value
    }

    private func isHorizontalDrag(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }
}
