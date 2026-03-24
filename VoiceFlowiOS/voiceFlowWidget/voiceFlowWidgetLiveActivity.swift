import ActivityKit
import WidgetKit
import SwiftUI

struct voiceFlowWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceFlowActivityAttributes.self) { context in
            // Lock screen/banner UI
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text("VoiceFlow 正在录制")
                        .font(.headline)
                    Text(context.state.status)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(context.state.startTime, style: .timer)
                    .font(.monospacedDigit(.body)())
                    .frame(width: 50)
            }
            .padding()
            .activityBackgroundTint(Color.white.opacity(0.8))
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startTime, style: .timer)
                        .font(.monospacedDigit(.body)())
                        .foregroundColor(.red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("VoiceFlow: \(context.state.status)")
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
            } compactTrailing: {
                Text(context.state.startTime, style: .timer)
                    .font(.monospacedDigit(.caption2)())
                    .frame(width: 40)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
            }
            .keylineTint(Color.red)
        }
    }
}
