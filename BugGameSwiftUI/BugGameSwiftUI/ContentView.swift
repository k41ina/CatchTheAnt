import SwiftUI
import CoreMotion
import AVFoundation
import UIKit // For share functionality

// MARK: - Bug Model

class BugModel: Identifiable, ObservableObject {
    let id = UUID()
    let emoji: String
    let isAnt: Bool
    @Published var position: CGPoint

    init(emoji: String, isAnt: Bool, position: CGPoint) {
        self.emoji = emoji
        self.isAnt = isAnt
        self.position = position
    }
}

// MARK: - Motion Manager

class MotionManager: ObservableObject {
    private var motionManager = CMMotionManager()
    private let queue = OperationQueue()

    @Published var didShake = false

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.accelerometerUpdateInterval = 0.2
        motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let data = data else { return }

            let acceleration = data.acceleration
            let magnitude = sqrt(acceleration.x * acceleration.x +
                                 acceleration.y * acceleration.y +
                                 acceleration.z * acceleration.z)

            if magnitude > 2.5 {
                DispatchQueue.main.async {
                    self?.didShake = true
                }
            }
        }
    }

    deinit {
        motionManager.stopAccelerometerUpdates()
    }
}

// MARK: - ContentView

struct ContentView: View {
    enum GameScreen {
        case start, rules, waitingForShake, waitingBeforeStart, game, result
    }

    @State private var currentScreen: GameScreen = .start
    @State private var bugs: [BugModel] = []
    @State private var gameOverMessage: String = ""
    @State private var startTime: Date?
    @State private var bugMovementTimer: Timer?

    @AppStorage("highScore") private var highScore: Double = .infinity
    @State private var showShareSheet = false
    @State private var reactionTimeToShare: String = ""

    @StateObject private var motionManager = MotionManager()
    @State private var audioPlayer: AVAudioPlayer?

    let bugSize: CGFloat = 50

    var body: some View {
        ZStack {
            Image(currentScreen == .start ? "startBackground" : "gameBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            switch currentScreen {
            case .start: startScreen
            case .rules: rulesScreen
            case .waitingForShake: waitingForShakeScreen
            case .waitingBeforeStart: waitingScreen
            case .game: gameScreen
            case .result: resultScreen
            }
        }
        .onChange(of: currentScreen) { if $0 == .waitingForShake { motionManager.didShake = false } }
    }

    var startScreen: some View {
        VStack {
            Spacer()
            Button("Play") { currentScreen = .rules }
                .font(.custom("Jersey 10", size: 32))
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(Color(hex: "F3A932"))
                .foregroundColor(.black)
                .cornerRadius(12)
            Spacer().frame(height: 100)
        }
    }

    var rulesScreen: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                VStack(alignment: .leading, spacing: 24) {
                    Text("How to Play")
                        .font(.custom("Jersey 10", size: 36))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .center)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("1. Shake your phone to start")
                        Text("2. Wait for the bugs to come")
                        Text("3. Tap on the ant to catch it\n   Be careful not to catch any\n   of the other bugs!")
                        Text("4. See how fast you reacted and try to beat your score!")
                    }
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.black)
                    HStack(spacing: 12) {
                        Button("Start") { currentScreen = .waitingForShake }
                            .font(.custom("Jersey 10", size: 24))
                            .padding(.horizontal, 30)
                            .padding(.vertical, 10)
                            .background(Color(hex: "F3A932"))
                            .foregroundColor(.black)
                            .cornerRadius(10)
                        Image("bugIcon")
                            .resizable()
                            .frame(width: 50, height: 50)
                    }
                    .padding(.top, 10)
                }
                .padding()
                .background(Color(hex: "E4C189"))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "F3A932"), lineWidth: 4))
                .cornerRadius(20)
                .padding(.horizontal, 30)
                Spacer()
            }
        }
    }

    var waitingForShakeScreen: some View {
        VStack(spacing: 20) {
            Text("Shake your phone to start!")
                .font(.custom("Jersey 10", size: 32))
                .padding()
                .background(Color(hex: "F3A932"))
                .foregroundColor(.black)
                .cornerRadius(12)
            ProgressView()
        }
        .onChange(of: motionManager.didShake) { if $0 { motionManager.didShake = false; performWaitThenStart() } }
    }

    var waitingScreen: some View {
        VStack {
            Spacer()
            Text("Wait for it...")
                .font(.custom("Jersey 10", size: 48))
                .padding()
                .background(Color(hex: "F3A932"))
                .foregroundColor(.black)
                .cornerRadius(20)
            Spacer()
        }
    }

    var gameScreen: some View {
        ZStack {
            ForEach(bugs) { BugView(bug: $0, onTapped: bugTapped) }
        }
    }

    var resultScreen: some View {
        VStack(spacing: 20) {
            Text(gameOverMessage)
                .font(.title2)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
            if highScore < .infinity {
                Text("🏆 Best Time: \(String(format: "%.2f", highScore)) seconds")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Button("Play Again") { currentScreen = .waitingForShake }
                .font(.headline)
                .padding()
                .background(Color.green.opacity(0.8))
                .foregroundColor(.white)
                .clipShape(Capsule())
            Button("Share Score") { showShareSheet = true }
                .font(.subheadline)
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .sheet(isPresented: $showShareSheet) {
            let message = reactionTimeToShare.isEmpty ? "Try this fun bug-catching reaction game!" : "I caught the ant in \(reactionTimeToShare) seconds! Can you beat my score?"
            ShareSheet(activityItems: [message])
        }
    }

    func performWaitThenStart() {
        currentScreen = .waitingBeforeStart
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 2...5)) {
            startGame()
        }
    }

    func startGame() {
        currentScreen = .game
        startTime = Date()
        bugs = []
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        func randomPosition() -> CGPoint {
            CGPoint(x: CGFloat.random(in: 40...(screenWidth - 40)), y: CGFloat.random(in: 150...(screenHeight - 100)))
        }
        bugs += (0..<2).map { _ in BugModel(emoji: "🐞", isAnt: false, position: randomPosition()) }
        bugs += (0..<2).map { _ in BugModel(emoji: "🪲", isAnt: false, position: randomPosition()) }
        bugs += (0..<2).map { _ in BugModel(emoji: "🐛", isAnt: false, position: randomPosition()) }
        bugs.append(BugModel(emoji: "🐜", isAnt: true, position: randomPosition()))
        startBugMovement()
    }

    func startBugMovement() {
        bugMovementTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            for bug in bugs {
                withAnimation(.easeInOut(duration: 0.8)) {
                    bug.position = CGPoint(x: CGFloat.random(in: 40...(screenWidth - 40)), y: CGFloat.random(in: 150...(screenHeight - 100)))
                }
            }
        }
    }

    func stopBugMovement() {
        bugMovementTimer?.invalidate()
        bugMovementTimer = nil
    }

    func bugTapped(_ bug: BugModel) {
        guard let start = startTime else { return }
        stopBugMovement()
        if bug.isAnt {
            let reactionTime = Date().timeIntervalSince(start)
            let formatted = String(format: "%.2f", reactionTime)
            gameOverMessage = "🎉 You caught the ant in \(formatted) seconds!"
            reactionTimeToShare = formatted
            if reactionTime < highScore { highScore = reactionTime }
            bugs = [bug]
            playWinSound { currentScreen = .result }
        } else {
            gameOverMessage = "💀 You tapped the wrong bug!"
            reactionTimeToShare = ""
            bugs.removeAll()
            currentScreen = .result
        }
    }

    func playWinSound(completion: @escaping () -> Void) {
        guard let url = Bundle.main.url(forResource: "winSound", withExtension: "mp3") else {
            print("Win sound file not found"); completion(); return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 0.5)) {
                completion()
            }
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
            completion()
        }
    }
}

struct BugView: View {
    @ObservedObject var bug: BugModel
    let onTapped: (BugModel) -> Void
    var body: some View {
        Text(bug.emoji)
            .font(.system(size: 50))
            .position(bug.position)
            .onTapGesture { onTapped(bug) }
            .transition(.scale)
            .animation(.easeInOut(duration: 0.8), value: bug.position)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
}
