import UIKit
import SpriteKit


// MARK: - View Controller
final class GameViewController: UIViewController {

    private var skView: SKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        skView = SKView()
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.ignoresSiblingOrder = true
        view.addSubview(skView)

        NSLayoutConstraint.activate([
            skView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skView.topAnchor.constraint(equalTo: view.topAnchor),
            skView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 2) 从 .sks 加载场景
        guard let scene = SKScene(fileNamed: "GameScene") as? GameScene else {
            fatalError("Could not load GameScene.sks")
        }

        scene.scaleMode = .aspectFit

        skView.presentScene(scene)
    }
}
