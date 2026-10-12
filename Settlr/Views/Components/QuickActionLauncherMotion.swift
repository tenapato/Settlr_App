/// The C6 launcher's spatial presentation for a single interaction state.
/// This stays UI-framework independent so motion accessibility remains easy
/// to verify without rendering the full tab shell.
struct QuickActionLauncherMotion {
    let symbolName: String
    let rotationDegrees: Double
    let scale: Double

    init(isOpen: Bool, isPressed: Bool, reduceMotion: Bool) {
        symbolName = reduceMotion && isOpen ? "xmark" : "plus"
        rotationDegrees = reduceMotion ? 0 : (isOpen ? 45 : 0)
        scale = reduceMotion ? 1 : (isPressed ? 0.94 : 1)
    }
}
