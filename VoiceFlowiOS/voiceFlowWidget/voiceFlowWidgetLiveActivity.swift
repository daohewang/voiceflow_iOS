import ActivityKit
import WidgetKit
import SwiftUI

struct voiceFlowWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceFlowActivityAttributes.self) { context in
            ZStack {
                Color.black
                VoiceFlowBrandMark(color: .white)
                    .frame(width: 72, height: 72)
            }
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VoiceFlowBrandMark(color: .white)
                        .frame(width: 96, height: 32)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } compactLeading: {
                VoiceFlowBrandMark(color: .white)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                VoiceFlowBrandMark(color: .white)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(.clear)
        }
    }
}

private struct VoiceFlowBrandMark: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let barWidth = width * 0.12
            let gap = width * 0.06
            let heights: [CGFloat] = [0.42, 0.68, 1.0, 0.84, 0.52]
            let totalWidth = barWidth * 5 + gap * 4
            let startX = (width - totalWidth) / 2

            HStack(alignment: .center, spacing: gap) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, ratio in
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: height * ratio)
                }
            }
            .frame(width: totalWidth, height: height)
            .position(x: startX + totalWidth / 2, y: height / 2)
        }
    }
}
