import UIKit
import SpriteKit


// MARK: - View Controller
class GameViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create the SpriteKit view
        let skView = SKView(frame: view.bounds)
        view.addSubview(skView)
        
        // Create and present the scene
        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .aspectFill
        skView.presentScene(scene)
    }
}
