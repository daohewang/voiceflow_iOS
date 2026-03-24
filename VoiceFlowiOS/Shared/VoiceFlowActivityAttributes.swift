import ActivityKit
import Foundation

struct VoiceFlowActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic state: e.g., how long we've been recording or current status text
        var status: String
        var startTime: Date
    }

    // Static data: e.g., user name or session ID
    var sessionName: String
}
