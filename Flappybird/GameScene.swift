//
//  GameScene.swift
//  Flappybird
//
//  Workshop version (Feature-Flagged):
//  - Multi-bird (manual tap flaps ALL birds) when AI mode is OFF
//  - Pipes move + spawn
//  - Collision kills bird
//  - Auto-restart when all birds are dead
//  - Uses .sks physics bodies (no rebuild)
//  - AI mode (regular / advanced) when enabled
//

import SpriteKit
import UIKit

// MARK: - Physics Categories
enum PhysicsCategory {
    static let bird: UInt32    = 1 << 0 // 0001
    static let pipe: UInt32    = 1 << 1 // 0010
    static let ground: UInt32  = 1 << 2 // 0100
    static let ceiling: UInt32 = 1 << 3 // 1000
}

// MARK: AI Mode
enum AIMode {
    case off
    case regular
    case advanced
}

// MARK: - Game Scene
final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: Feature Flags
    private let aiMode: AIMode = .off
    // .off / .regular / .advanced

    // MARK: AI (only created if mode is not OFF)
    private lazy var ai: FlappyAIProtocol? = {
        switch aiMode {
        case .off:
            return nil
        case .regular:
            return FlappyAI(popSize: birdCount)
        case .advanced:
            return AdvancedFlappyAI(popSize: birdCount)
        }
    }()

    private var isAIModeEnabled: Bool { ai != nil }

    // time/distance used as fitness
    private var runTime = Double(0)

    // MARK: Scene nodes loaded from GameScene.sks
    private var world: SKNode!               // Root container for all moving objects
    private var birdPrototype: SKSpriteNode! // Template bird used for cloning
    private var pipePrototype: SKNode!       // Template pipe pair used for cloning
    private var groundNode: SKSpriteNode!    // Invisible collision ground
    private var ceilingNode: SKSpriteNode!   // Invisible collision ceiling

    // MARK: Birds
    private var birds = [SKSpriteNode]()
    // ADJUSTABLE: Number of birds to spawn
    private let birdCount = Int(1)

    // MARK: Pipes
    private var pipes = [Pipe]()

    // Gameplay-controlled pipe gap.
    private var pipeGap = CGFloat(130)   // Vertical opening between pipes, overwritten from SKS in didMove()
    // ADJUSTABLE: Leftward (moving to the left) movement speed
    private let pipeSpeed = CGFloat(-2.5)   // Larger absolute value = faster movement.
    // ADJUSTABLE: Distance between pipe spawns
    private let spawnDist = CGFloat(400)

    private var pipeSpawnProgress = CGFloat(0)

    // MARK: Physics tuning

    // ADJUSTABLE: Downward gravity applied to birds.
    private let gravityY = CGFloat(-12)

    // ADJUSTABLE: Upward velocity applied when a bird flaps.
    private var flapVelocityTarget = CGFloat(320)   // Computed again in didMove() to match world scale.

    // MARK: Timing & state
    private var lastUpdateTime = TimeInterval(0)
    private var didInit = Bool(false)

    private var gameOver = Bool(false)
    private var restartAt: TimeInterval? = nil

    // MARK: HUD
    private var scoreLbl: SKLabelNode?
    private var bestLbl: SKLabelNode?
    private var score = Int(0)
    private var best = Int(0)

    // MARK: Scene setup
    override func didMove(to view: SKView) {
        guard !didInit else { return }
        didInit = true

        physicsWorld.gravity = CGVector(dx: 0, dy: gravityY)
        physicsWorld.contactDelegate = self

        // Prefer // paths so SKS hierarchy changes don't break lookups
        guard let w = childNode(withName: "World") else {
            fatalError("Missing node named World")
        }
        world = w

        guard let bp = w.childNode(withName: "birdPrototype") as? SKSpriteNode else {
            fatalError("Missing SKSpriteNode named birdPrototype")
        }
        birdPrototype = bp
//        bp.texture = SKTexture(imageNamed: "bird")

        birdPrototype.removeFromParent()

        guard let pp = w.childNode(withName: "pipePrototype") else {
            fatalError("Missing node named pipePrototype")
        }
        pipePrototype = pp
        pipePrototype.removeFromParent()

        guard let g = w.childNode(withName: "ground") as? SKSpriteNode else {
            fatalError("Missing node named ground")
        }
        guard let c = w.childNode(withName: "ceiling") as? SKSpriteNode else {
            fatalError("Missing node named ceiling")
        }
        groundNode = g
        ceilingNode = c

        guard let hud = childNode(withName: "HUD") else {
            fatalError("Missing node named HUD")
        }

        scoreLbl = hud.childNode(withName: "scoreLabel") as? SKLabelNode
        bestLbl  = hud.childNode(withName: "bestLabel")  as? SKLabelNode
        pipeGap = computeGapFromPipePrototypeFrames(
            template: pipePrototype,
            minGap: CGFloat(80)
        )

        flapVelocityTarget = computeFlapVelocityTarget()

        resetGame()
    }

    // MARK: Coordinate helpers (Scene <-> World)
    private func sceneToWorld(_ p: CGPoint) -> CGPoint {
        world.convert(p, from: self)
    }

    private func sceneXToWorld(_ x: CGFloat) -> CGFloat {
        sceneToWorld(CGPoint(x: x, y: CGFloat(0))).x
    }

    // MARK: Gap calculation
    private func computeGapFromPipePrototypeFrames(
        template: SKNode,
        minGap: CGFloat
    ) -> CGFloat {

        // NOTE: `template` is already the pipePrototype node; search within it.
        guard
            let top = template.childNode(withName: "pipeTop") as? SKSpriteNode,
            let bot = template.childNode(withName: "pipeBottom") as? SKSpriteNode
        else {
            return max(CGFloat(130), minGap)
        }

        let gap = top.frame.minY - bot.frame.maxY
        return max(gap, minGap)
    }

    // MARK: Flap tuning
    private func computeFlapVelocityTarget() -> CGFloat {
        let birdHeight = birdPrototype.size.height * birdPrototype.yScale
        let baseline = CGFloat(16)
        let sizeScale = max(CGFloat(0.8), min(CGFloat(2.0), birdHeight / baseline))
        let worldScale = max(CGFloat(0.001), world.yScale)
        return (CGFloat(320) * sizeScale) / worldScale
    }

    // MARK: Reset game state
    private func resetGame() {
        gameOver = false
        restartAt = nil
        lastUpdateTime = TimeInterval(0)

        score = Int(0)
        updateHUD()

        // Remove all pipes
        pipes.forEach { $0.remove() }
        pipes.removeAll()
        pipeSpawnProgress = CGFloat(0)

        // Remove all birds
        birds.forEach { $0.removeFromParent() }
        birds.removeAll()

        spawnBirds()
        spawnPipe()

        // NN run reset
        runTime = Double(0)
        ai?.resetRunState()
    }

    // MARK: Bird spawning
    private func spawnBirds() {
        let birdXScene = frame.minX + frame.width * CGFloat(0.2)
        let baseYScene = frame.midY

        for _ in 0..<birdCount {
            guard let b = birdPrototype.copy() as? SKSpriteNode else {
                fatalError("birdPrototype must be an SKSpriteNode")
            }

            // Match prototype visuals (important when copying from SKS)
            b.size = birdPrototype.size
            b.xScale = birdPrototype.xScale
            b.yScale = birdPrototype.yScale
            b.zPosition = birdPrototype.zPosition

            b.position = sceneToWorld(CGPoint(x: birdXScene, y: baseYScene))

            guard let body = b.physicsBody else {
                fatalError("birdPrototype must have a physicsBody set in the Scene Editor")
            }

            body.categoryBitMask = PhysicsCategory.bird
            body.contactTestBitMask =
                PhysicsCategory.pipe |
                PhysicsCategory.ground |
                PhysicsCategory.ceiling
            body.collisionBitMask =
                PhysicsCategory.pipe |
                PhysicsCategory.ground |
                PhysicsCategory.ceiling

            birds.append(b)
            world.addChild(b)
        }
    }

    // MARK: HUD update
    private func updateHUD() {
        scoreLbl?.text = "Current: \(score)"
        bestLbl?.text = "Best: \(best)"
    }

    // MARK: Pipe spawning
    private func spawnPipe() {
        let worldMinY = groundNode.frame.maxY
        let worldMaxY = ceilingNode.frame.minY

        let minGapCenter = worldMinY + pipeGap * CGFloat(0.5)
        let maxGapCenter = worldMaxY - pipeGap * CGFloat(0.5)

        let gapYWorld: CGFloat
        if minGapCenter < maxGapCenter {
            gapYWorld = CGFloat.random(in: minGapCenter...maxGapCenter)
        } else {
            gapYWorld = (worldMinY + worldMaxY) * CGFloat(0.5)
        }

        let xWorld = sceneXToWorld(frame.maxX + CGFloat(60))

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

    // MARK: Input
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Manual mode only
        if !isAIModeEnabled {
            flapAll()
        }
    }

    private func flapAll() {
        for b in birds {
            guard let body = b.physicsBody, body.isDynamic else { continue }
            body.velocity = CGVector(dx: body.velocity.dx, dy: flapVelocityTarget)
        }
    }

    // MARK: Collision handling
    func didBegin(_ contact: SKPhysicsContact) {
        let birdBody: SKPhysicsBody?

        if contact.bodyA.categoryBitMask == PhysicsCategory.bird {
            birdBody = contact.bodyA
        } else if contact.bodyB.categoryBitMask == PhysicsCategory.bird {
            birdBody = contact.bodyB
        } else {
            birdBody = nil
        }

        guard let bBody = birdBody,
              let node = bBody.node as? SKSpriteNode else { return }

        killBird(node)
    }

    private func killBird(_ bird: SKSpriteNode) {
        guard let idx = birds.firstIndex(where: { $0 === bird }) else { return }

        let b = birds[idx]
        b.alpha = CGFloat(0)
        b.physicsBody?.isDynamic = false

        // NN fitness tracking
        if isAIModeEnabled {
            ai?.tickAlive(i: idx, distance: runTime)
            ai?.kill(i: idx)
        }

        // If all birds are dead, evolve (if enabled) and restart
        if birds.allSatisfy({ $0.physicsBody?.isDynamic == false }) {
            if isAIModeEnabled {
                ai?.evolve()
            }
            triggerGameOver()
        }
    }

    private func triggerGameOver() {
        guard !gameOver else { return }
        gameOver = true
        restartAt = lastUpdateTime + TimeInterval(0.6)
    }

    // MARK: Game loop
    override func update(_ currentTime: TimeInterval) {

        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = TimeInterval(1.0 / 60.0)
        } else {
            dt = currentTime - lastUpdateTime
        }
        lastUpdateTime = currentTime

        // Auto-restart after game over
        if gameOver {
            if let t = restartAt, currentTime >= t {
                resetGame()
            }
            return
        }

        // Move pipes left
        for p in pipes { p.move(pipeSpeed) }

        // Remove pipes that leave the screen
        let leftWorld = sceneXToWorld(frame.minX)
        pipes.removeAll { p in
            if p.x < leftWorld - CGFloat(120) {
                p.remove()
                return true
            }
            return false
        }

        // Spawn new pipes based on distance traveled
        pipeSpawnProgress += abs(pipeSpeed)
        if pipeSpawnProgress >= spawnDist {
            spawnPipe()
            pipeSpawnProgress = CGFloat(0)
        }

        // Scoring logic (lead alive bird passes a pipe)
        let aliveBirds = birds.filter { $0.physicsBody?.isDynamic == true }
        if let lead = aliveBirds.max(by: { $0.position.x < $1.position.x }) {
            let leadX = lead.position.x
            for p in pipes {
                if !p.passed && p.x + CGFloat(35) < leadX {
                    p.passed = true
                    score += 1

                    if isAIModeEnabled {
                        for i in birds.indices {
                            if birds[i].physicsBody?.isDynamic == true {
                                ai?.addScore(i: i)
                            }
                        }
                    }

                    best = max(best, score)
                    updateHUD()
                }
            }
        }

        // NN update loop
        runTime += dt

        if isAIModeEnabled {

            let worldMinY = groundNode.frame.maxY
            let worldMaxY = ceilingNode.frame.minY
            let h = Double(worldMaxY - worldMinY)

            let refX = sceneXToWorld(frame.minX + frame.width * CGFloat(0.2))
            let nextPipe = pipes.first { $0.x + CGFloat(22) > refX }

            for (i, b) in birds.enumerated() {

                guard let body = b.physicsBody, body.isDynamic else { continue }

                ai?.tickAlive(i: i, distance: runTime)

                let birdY = Double(b.position.y - worldMinY)
                let velY  = Double(body.velocity.dy)

                let topY: Double
                let botY: Double
                let dist: Double

                if let p = nextPipe {
                    topY = Double(p.gapTopY - worldMinY)
                    botY = Double(p.gapBotY - worldMinY)
                    dist = Double(max(0, p.x - b.position.x))
                } else {
                    topY = h
                    botY = 0
                    dist = 600
                }

                if ai?.shouldFlap(
                    birdIndex: i,
                    birdY: birdY,
                    topY: topY,
                    botY: botY,
                    dist: dist,
                    velY: velY,
                    height: h
                ) == true {
                    body.velocity = CGVector(
                        dx: body.velocity.dx,
                        dy: flapVelocityTarget
                    )
                }
            }
        }
    }
}
