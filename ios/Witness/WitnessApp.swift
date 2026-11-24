// Witness for iPhone and iPad: the web app, bundled and run in a full-screen web view.
// The app's files (index.html, the audio worklets, vendor/) are copied into the app at build time
// (see the "Bundle the web app" build phase) and served from a tiny local web server, so the camera,
// audio worklets, module workers and WebAssembly all behave exactly as they do on the web.
import SwiftUI

@main
struct WitnessApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var server = LocalServer.shared

    init() { LocalServer.shared.start() }

    private var startURL: URL { server.baseURL.appendingPathComponent("index.html") }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color("LaunchBackground").ignoresSafeArea()
                if server.ready {
                    // Kept inside the safe area, so the page never sits under the notch or home indicator.
                    WitnessWebView(url: startURL)
                } else if let err = server.error {
                    Text("Witness couldn't start its local server.\n\(err)")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS can tear down the listening socket while the app is suspended; bring it back.
            if phase == .active { LocalServer.shared.start() }
        }
    }
}
