// The widget extension's starting point. Lists everything it provides: the
// Today home screen widget and the rest timer's Lock Screen / Dynamic Island view.
// This runs separately from the app. It gets its data from WidgetSnapshot.

import WidgetKit
import SwiftUI

@main
struct EverydayWidgetBundle: WidgetBundle {
    var body: some Widget {
        EverydayWidget()
        RestTimerLiveActivity()
    }
}
