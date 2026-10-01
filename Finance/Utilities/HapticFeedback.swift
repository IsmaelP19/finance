import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum HapticFeedback {
    @MainActor
    static func success() {
#if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
#endif
    }
}
