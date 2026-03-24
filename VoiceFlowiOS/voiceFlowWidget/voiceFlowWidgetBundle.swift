//
//  voiceFlowWidgetBundle.swift
//  voiceFlowWidget
//
//  Created by 叶Sir on 2026/3/23.
//

import WidgetKit
import SwiftUI

@main
struct voiceFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        voiceFlowWidget()
        voiceFlowWidgetControl()
        voiceFlowWidgetLiveActivity()
    }
}
