/// What the menu-bar panel shows about the watch loop: its state, the meeting
/// being recorded, and the last error.
struct TranscriberStatus {
    let state: TranscriberState
    let meeting: MeetingInfo?
    let error: String?
}

/// The watch loop's state, as the panel names it.
typealias TranscriberState = WatchLoop.State

extension WatchLoop.State {
    var label: String {
        switch self {
        case .idle: "Idle"
        case .watching: "Watching for meetings…"
        case .recording: "Recording"
        case .error: "Error"
        }
    }
}

struct MeetingInfo {
    let app: String
    let title: String
}
