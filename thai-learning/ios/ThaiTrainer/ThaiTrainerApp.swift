import SwiftUI

@main
struct ThaiTrainerApp: App {
    @StateObject private var lessonStore = LessonStore()
    @StateObject private var audioPlayer = LocalAudioPlayer()

    var body: some Scene {
        WindowGroup {
            TrainerView(lessonStore: lessonStore, audioPlayer: audioPlayer)
        }
    }
}
