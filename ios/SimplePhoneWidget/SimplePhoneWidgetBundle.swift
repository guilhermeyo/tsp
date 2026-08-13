import WidgetKit
import SwiftUI

@main
struct SimplePhoneWidgetBundle: WidgetBundle {
    var body: some Widget {
        LauncherWidget()
        WeatherWidget()
    }
}
