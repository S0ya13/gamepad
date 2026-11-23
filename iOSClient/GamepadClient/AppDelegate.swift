import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = GamepadViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        UIApplication.shared.isIdleTimerDisabled = true  // no auto-lock mid-game
        if let url = options.urlContexts.first?.url { controller.pair(with: url) }  // launched from the QR link
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        (window?.rootViewController as? GamepadViewController)?.pair(with: url)
    }
}
