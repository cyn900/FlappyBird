//
//  GameScene.swift
//  Flappybird
//
//  Manual (tap to flap) — uses .sks physics body (no rebuild)
//

import SpriteKit
import UIKit

private enum PhysicsCategory {
    static let bird: UInt32   = 1 << 0
    static let pipe: UInt32   = 1 << 1
    static let ground: UInt32 = 1 << 2
    static let ceiling: UInt32 = 1 << 3
}

final class Pipe {
    let node: SKNode
    let top: SKSpriteNode
    let bot: SKSpriteNode

    var passed = false
    var x: CGFloat { node.position.x }

    init(
        template: SKNode,
        xPosInWorld: CGFloat,
        gapYInWorld: CGFloat,
        gap: CGFloat,
        worldMinY: CGFloat,
        worldMaxY: CGFloat
    ) {
        guard let copy = template.copy() as? SKNode else {
            fatalError("pipePrototype must be an SKNode")
        }
        self.node = copy
        self.node.position = CGPoint(x: xPosInWorld, y: 0)

        guard
            let t = copy.childNode(withName: "//pipeTop") as? SKSpriteNode,
            let b = copy.childNode(withName: "//pipeBottom") as? SKSpriteNode
        else {
            fatalError("pipePrototype must have children named pipeTop and pipeBottom (Sprite Nodes)")
        }

        self.top = t
        self.bot = b

        let gapTopY = gapYInWorld + gap * 0.5
        let gapBotY = gapYInWorld - gap * 0.5

        let topH = max(10, worldMaxY - gapTopY)
        let botH = max(10, gapBotY - worldMinY)

        top.size.height = topH
        bot.size.height = botH

        top.position = CGPoint(x: top.position.x, y: gapTopY + topH * 0.5)
        bot.position = CGPoint(x: bot.position.x, y: worldMinY + botH * 0.5)

        top.physicsBody = SKPhysicsBody(rectangleOf: top.size)
        bot.physicsBody = SKPhysicsBody(rectangleOf: bot.size)

        for p in [top, bot] {
            p.physicsBody?.isDynamic = false
            p.physicsBody?.restitution = 0
            p.physicsBody?.friction = 0
            p.physicsBody?.categoryBitMask = PhysicsCategory.pipe
            p.physicsBody?.contactTestBitMask = PhysicsCategory.bird
            p.physicsBody?.collisionBitMask = PhysicsCategory.bird
        }
    }

    func move(_ dx: CGFloat) { node.position.x += dx }
    func remove() { node.removeFromParent() }
}

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private var world: SKNode!
    private var birdPrototype: SKSpriteNode!
    private var pipePrototype: SKNode!
    private var groundNode: SKSpriteNode!
    private var ceilingNode: SKSpriteNode!

    private var bird: SKSpriteNode!
    private var pipes: [Pipe] = []

    private var pipeGap: CGFloat = 130

    // Physics
    private let gravityY: CGFloat = -12

    // ✅ Instead of “dy: 4”, compute flap strength from mass (works even if mass is large)
    private var flapVelocityTarget: CGFloat = 320   // desired upward speed after tap (tunable)

    private let pipeSpeed: CGFloat = -2.5
    private let spawnDist: CGFloat = 280
    private var pipeSpawnProgress: CGFloat = 0

    private var lastUpdateTime: TimeInterval = 0
    private var didInit = false
    private var gameOver = false

    private var scoreLbl: SKLabelNode?
    private var bestLbl: SKLabelNode?
    private var score = 0
    private var best = 0

    override func didMove(to view: SKView) {
        guard !didInit else { return }
        didInit = true

        physicsWorld.gravity = CGVector(dx: 0, dy: gravityY)
        physicsWorld.contactDelegate = self

        guard let w = childNode(withName: "//World") else { fatalError("Missing node named World") }
        world = w

        guard let bp = childNode(withName: "//birdPrototype") as? SKSpriteNode else {
            fatalError("Missing SKSpriteNode named birdPrototype")
        }
        birdPrototype = bp
        birdPrototype.removeFromParent()

        guard let pp = childNode(withName: "//pipePrototype") as? SKNode else {
            fatalError("Missing node named pipePrototype")
        }
        pipePrototype = pp
        pipePrototype.removeFromParent()

        guard let g = childNode(withName: "//ground") as? SKSpriteNode else {
            fatalError("Missing node named ground")
        }
        guard let c = childNode(withName: "//ceiling") as? SKSpriteNode else {
            fatalError("Missing node named ceiling")
        }
        groundNode = g
        ceilingNode = c
        
        // Ground physics
        groundNode.physicsBody = SKPhysicsBody(rectangleOf: groundNode.size)
        groundNode.physicsBody?.isDynamic = false
        groundNode.physicsBody?.restitution = 0
        groundNode.physicsBody?.friction = 0
        groundNode.physicsBody?.categoryBitMask = PhysicsCategory.ground
        groundNode.physicsBody?.contactTestBitMask = PhysicsCategory.bird
        groundNode.physicsBody?.collisionBitMask = PhysicsCategory.bird

        // Ceiling physics
        ceilingNode.physicsBody = SKPhysicsBody(rectangleOf: ceilingNode.size)
        ceilingNode.physicsBody?.isDynamic = false
        ceilingNode.physicsBody?.restitution = 0
        ceilingNode.physicsBody?.friction = 0
        ceilingNode.physicsBody?.categoryBitMask = PhysicsCategory.ceiling
        ceilingNode.physicsBody?.contactTestBitMask = PhysicsCategory.bird
        ceilingNode.physicsBody?.collisionBitMask = PhysicsCategory.bird

        scoreLbl = childNode(withName: "//scoreLabel") as? SKLabelNode
        bestLbl  = childNode(withName: "//bestLabel")  as? SKLabelNode

        pipeGap = computeGapFromPipePrototypeFrames(template: pipePrototype, minGap: 80)

        // ✅ Make “tap feel” proportional to bird size AND world scale
        let birdHeight = birdPrototype.size.height * birdPrototype.yScale
        let baseline: CGFloat = 16
        let sizeScale = max(0.8, min(2.0, birdHeight / baseline))
        let worldScale = max(0.001, world.yScale)

        // target upward velocity in WORLD coords
        flapVelocityTarget = (320 * sizeScale) / worldScale

        resetGame()
    }

    // MARK: - Coordinate helpers
    private func sceneToWorld(_ p: CGPoint) -> CGPoint { world.convert(p, from: self) }
    private func sceneXToWorld(_ x: CGFloat) -> CGFloat { sceneToWorld(CGPoint(x: x, y: 0)).x }
    private func sceneYToWorld(_ y: CGFloat) -> CGFloat { sceneToWorld(CGPoint(x: 0, y: y)).y }

    private func computeGapFromPipePrototypeFrames(template: SKNode, minGap: CGFloat) -> CGFloat {
        guard
            let top = template.childNode(withName: "//pipeTop") as? SKSpriteNode,
            let bot = template.childNode(withName: "//pipeBottom") as? SKSpriteNode
        else { return max(130, minGap) }

        let gap = top.frame.minY - bot.frame.maxY
        return max(gap, minGap)
    }

    private func resetGame() {
        gameOver = false
        score = 0
        updateHUD()

        pipes.forEach { $0.remove() }
        pipes.removeAll()
        pipeSpawnProgress = 0

        bird?.removeFromParent()

        guard let b = birdPrototype.copy() as? SKSpriteNode else {
            fatalError("birdPrototype must be an SKSpriteNode")
        }
        bird = b
        bird.size = birdPrototype.size
        bird.xScale = birdPrototype.xScale
        bird.yScale = birdPrototype.yScale
        bird.zPosition = birdPrototype.zPosition

        let birdXScene = frame.minX + frame.width * 0.2
        let startPosScene = CGPoint(x: birdXScene, y: frame.midY)
        bird.position = sceneToWorld(startPosScene)

        // ✅ Do NOT rebuild. But DO force critical flags on the copied body.
        guard let body = bird.physicsBody else {
            fatalError("birdPrototype must have a physicsBody set in the Scene Editor")
        }

        body.isDynamic = true
        body.affectedByGravity = true
        body.allowsRotation = false
        body.restitution = 0
        body.friction = 0
        body.linearDamping = 0
        body.angularDamping = 0

        // ✅ Important: allow the body to move even if it was pinned in editor
        body.pinned = false

        body.categoryBitMask = PhysicsCategory.bird
        body.contactTestBitMask = PhysicsCategory.pipe | PhysicsCategory.ground | PhysicsCategory.ceiling
        body.collisionBitMask = PhysicsCategory.pipe | PhysicsCategory.ground | PhysicsCategory.ceiling

        world.addChild(bird)

        spawnPipe()
    }

    private func updateHUD() {
        scoreLbl?.text = "Score: \(score)"
        bestLbl?.text = "Best: \(best)"
    }

    private func spawnPipe() {
        let groundTopScene = groundNode.frame.maxY
        let ceilingBottomScene = ceilingNode.frame.minY

        let worldMinY = sceneYToWorld(groundTopScene)
        let worldMaxY = sceneYToWorld(ceilingBottomScene)

        let minGapCenterScene = groundTopScene + pipeGap * 0.5
        let maxGapCenterScene = ceilingBottomScene - pipeGap * 0.5

        let gapYScene: CGFloat
        if minGapCenterScene < maxGapCenterScene {
            gapYScene = CGFloat.random(in: minGapCenterScene...maxGapCenterScene)
        } else {
            gapYScene = (groundTopScene + ceilingBottomScene) * 0.5
        }
        let gapYWorld = sceneYToWorld(gapYScene)

        let xWorld = sceneXToWorld(frame.maxX + 60)

        let pipe = Pipe(
            template: pipePrototype,
            xPosInWorld: xWorld,
            gapYInWorld: gapYWorld,
            gap: pipeGap,
            worldMinY: worldMinY,
            worldMaxY: worldMaxY
        )

        pipes.append(pipe)
        world.addChild(pipe.node)
    }

    // MARK: - Tap to flap (no rebuild; mass-proof)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if gameOver {
            resetGame()
            return
        }
        flap()
    }

    private func flap() {
        guard let body = bird.physicsBody else { return }

        // ✅ Set velocity directly (feels like original, but works even if mass is huge)
        // This avoids “impulse too small” problems without rebuilding.
        body.velocity = CGVector(dx: body.velocity.dx, dy: flapVelocityTarget)
    }

    // MARK: - Contact
    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA.categoryBitMask
        let b = contact.bodyB.categoryBitMask

        let birdHitSomething =
            (a == PhysicsCategory.bird && (b == PhysicsCategory.pipe || b == PhysicsCategory.ground || b == PhysicsCategory.ceiling)) ||
            (b == PhysicsCategory.bird && (a == PhysicsCategory.pipe || a == PhysicsCategory.ground || a == PhysicsCategory.ceiling))

        if birdHitSomething {
            triggerGameOver()
        }
    }

    private func triggerGameOver() {
        guard !gameOver else { return }
        gameOver = true
        bird.physicsBody?.isDynamic = false
    }

    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime == 0 { dt = 1.0 / 60.0 }
        else { dt = currentTime - lastUpdateTime }
        lastUpdateTime = currentTime

        if gameOver { return }

        for p in pipes { p.move(pipeSpeed) }

        let leftWorld = sceneXToWorld(frame.minX)
        pipes.removeAll { p in
            if p.x < leftWorld - 120 {
                p.remove()
                return true
            }
            return false
        }

        pipeSpawnProgress += abs(pipeSpeed)
        if pipeSpawnProgress >= spawnDist {
            spawnPipe()
            pipeSpawnProgress = 0
        }

        let birdXWorld = bird.position.x
        for p in pipes {
            if !p.passed && p.x + 22 < birdXWorld {
                p.passed = true
                score += 1
                best = max(best, score)
                updateHUD()
            }
        }

    }
}
