import SwiftUI

@main
struct ThaiTrainerApp: App {
    @StateObject private var lessonStore = LessonStore()
    @StateObject private var practicePlayer = PracticeSessionPlayer()
    @StateObject private var learningProgress = LearningProgressStore()

    var body: some Scene {
        WindowGroup {
            TrainerView(
                lessonStore: lessonStore,
                practicePlayer: practicePlayer,
                learningProgress: learningProgress
            )
        }
    }
}
