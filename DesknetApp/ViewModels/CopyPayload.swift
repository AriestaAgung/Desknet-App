import Foundation

/// What a copy button puts on the pasteboard. The app delegate does the pasteboard write.
enum CopyPayload: Equatable {
    case text(String)
    /// Raw image bytes as captured (PNG, JPEG, GIF, WEBP...).
    case image(Data)
    /// SVG markup. Pasted as SVG and as text, plus a bitmap when the system can draw it.
    case svg(Data)
}
