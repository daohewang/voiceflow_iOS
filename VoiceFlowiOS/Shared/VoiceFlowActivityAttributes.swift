import ActivityKit
import Foundation

struct VoiceFlowActivityAttributes: ActivityAttributes {
    enum LiveActivityMode: String, Codable, Hashable {
        case armed
        case recording
        case processing
    }

    public struct ContentState: Codable, Hashable {
        var mode: LiveActivityMode
        var startTime: Date
    }

    var sessionName: String
}
