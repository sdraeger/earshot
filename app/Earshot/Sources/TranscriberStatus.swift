/// What the menu-bar panel shows about the watch loop: its state, the meeting
/// being recorded, and the last error.
struct TranscriberStatus {
    let state: TranscriberState
    let meeting: MeetingInfo?
    let error: String?
}

/// The watch loop's state as the panel presents it (`WatchLoop.transcriberState`).
enum TranscriberState {
    case idle
    case watching
    case recording
    case error

    var label: String {
        switch self {
        case .idle: "Idle"
        case .watching: "Watching for meetings…"
        case .recording: "Recording"
        case .error: "Error"
        }
    }

    var icon: String {
        switch self {
        case .idle: "waveform.circle"
        case .watching: "eye.fill"
        case .recording: "record.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

struct MeetingInfo {
    let app: String
    let title: String
}
