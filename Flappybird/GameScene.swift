//
//  GameScene.swift
//  Flappybird
//
//  Workshop version (PRE-NN):
//  - Multi-bird (manual tap flaps ALL birds)
//  - Pipes move + spawn
//  - Collision kills bird
//  - Auto-restart when all birds are dead
//  - Uses .sks physics bodies (no rebuild)
//

import SpriteKit
import UIKit

// MARK: - Physics Categories
// Each physics body in SpriteKit belongs to one or more categories.
// These bitmasks let us control which objects collide or trigger contacts.
enum PhysicsCategory {
    static let bird: UInt32    = 1 << 0
    static let pipe: UInt32    = 1 << 1
    static let ground: UInt32  = 1 << 2
    static let ceiling: UInt32 = 1 << 3
}

// MARK: - Game Scene
// This is the main game loop controller.
// It owns the world, spawns birds and pipes, handles input, collisions, and scoring.
final class GameScene: SKScene, SKPhysicsContactDelegate {
    
//    // [NN] Step 1
//    //Create AI manager (the class lives in another file)
//    private lazy var ai = FlappyAI(popSize: birdCount)
//    // time/distance used as fitness
//    private var runTime: Double = 0


    // MARK: Scene nodes loaded from GameScene.sks
    // These are defined visually in the SpriteKit Scene Editor.
    private var world: SKNode!              // Root container for all moving objects
    private var birdPrototype: SKSpriteNode! // Template bird used for cloning
    private var pipePrototype: SKNode!       // Template pipe pair used for cloning
    private var groundNode: SKSpriteNode!    // Invisible collision ground
    private var ceilingNode: SKSpriteNode!   // Invisible collision ceiling

    // MARK: Birds
    // Supports multiple birds (useful for experiments or AI later)
    private var birds: [SKSpriteNode] = []
    
    // ADJUSTABLE: Number of birds to spawn
    private let birdCount = 1

    // MARK: Pipes
    private var pipes: [Pipe] = []
    
    // Gameplay-controlled pipe gap.
    // This default value is a fallback and will be
    // OVERWRITTEN after reading the pipe prototype from the SKS file in didMove().
    private var pipeGap: CGFloat = 130       // Vertical opening between pipes
    
    // ADJUSTABLE: Leftward (moving to the left) movement speed
    private let pipeSpeed: CGFloat = -2.5    // Larger absolute value = faster movement.
    
    // ADJUSTABLE: Distance between pipe spawns
    private let spawnDist: CGFloat = 300
    
    private var pipeSpawnProgress: CGFloat = 0

    // MARK: Physics tuning
    // ADJUSTABLE (game feel): Downward gravity applied to birds.
    private let gravityY: CGFloat = -12
    
    // ADJUSTABLE (game feel): Upward velocity applied when a bird flaps.
    private var flapVelocityTarget: CGFloat = 320  // Computed again in didMove() to match sprite/world scale.

    // MARK: Timing & state
    private var lastUpdateTime: TimeInterval = 0
    private var didInit = false               // Prevents double initialization

    private var gameOver = false
    private var restartAt: TimeInterval? = nil

    // MARK: HUD (Heads-Up Display)
    private var scoreLbl: SKLabelNode?
    private var bestLbl: SKLabelNode?
    private var score = 0
    private var best = 0

    // MARK: Scene setup
    override func didMove(to view: SKView) {
        // didMove can be called multiple times; guard ensures one-time setup
        guard !didInit else { return }
        didInit = true

        // Configure physics world
        physicsWorld.gravity = CGVector(dx: 0, dy: gravityY)
        physicsWorld.contactDelegate = self

        // Fetch nodes created in the .sks file
        guard let w = childNode(withName: "//World") else {
            fatalError("Missing node named World")
        }
        world = w

        // Load bird prototype and remove it from the scene
        // (we will clone it at runtime)
        guard let bp = childNode(withName: "//birdPrototype") as? SKSpriteNode else {
            fatalError("Missing SKSpriteNode named birdPrototype")
        }
        birdPrototype = bp
        birdPrototype.removeFromParent()

        // Load pipe prototype and remove it from the scene
        guard let pp = childNode(withName: "//pipePrototype") else {
            fatalError("Missing node named pipePrototype")
        }
        pipePrototype = pp
        pipePrototype.removeFromParent()

        // Ground and ceiling are collision boundaries
        guard let g = childNode(withName: "//ground") as? SKSpriteNode else {
            fatalError("Missing node named ground")
        }
        guard let c = childNode(withName: "//ceiling") as? SKSpriteNode else {
            fatalError("Missing node named ceiling")
        }
        groundNode = g
        ceilingNode = c

        // HUD labels
        scoreLbl = childNode(withName: "//scoreLabel") as? SKLabelNode
        bestLbl  = childNode(withName: "//bestLabel")  as? SKLabelNode

        // Compute gap size dynamically from the pipe prototype
        pipeGap = computeGapFromPipePrototypeFrames(
            template: pipePrototype,
            minGap: 80
        )

        // Compute flap strength so the game feels consistent at different scales
        flapVelocityTarget = computeFlapVelocityTarget()

        resetGame()
    }

    // MARK: Coordinate helpers (Scene <-> World)
    // Converts points from the scene coordinate system into the world node.
    private func sceneToWorld(_ p: CGPoint) -> CGPoint {
        world.convert(p, from: self)
    }

    private func sceneXToWorld(_ x: CGFloat) -> CGFloat {
        sceneToWorld(CGPoint(x: x, y: 0)).x
    }

    // MARK: Gap calculation
    // Reads the visual gap from the prototype pipes in the SKS file.
    private func computeGapFromPipePrototypeFrames(
        template: SKNode,
        minGap: CGFloat
    ) -> CGFloat {

        guard
            let top = template.childNode(withName: "//pipeTop") as? SKSpriteNode,
            let bot = template.childNode(withName: "//pipeBottom") as? SKSpriteNode
        else {
            return max(130, minGap)
        }

        let gap = top.frame.minY - bot.frame.maxY
        return max(gap, minGap)
    }

    // MARK: Flap tuning
    // Adjusts flap strength based on bird size and world scale.
    private func computeFlapVelocityTarget() -> CGFloat {
        let birdHeight = birdPrototype.size.height * birdPrototype.yScale
        let baseline: CGFloat = 16
        let sizeScale = max(0.8, min(2.0, birdHeight / baseline))
        let worldScale = max(0.001, world.yScale)
        return (320 * sizeScale) / worldScale
    }

    // MARK: Reset game state
    private func resetGame() {
        gameOver = false
        restartAt = nil
        lastUpdateTime = 0

        score = 0
        updateHUD()

        // Remove all pipes
        pipes.forEach { $0.remove() }
        pipes.removeAll()
        pipeSpawnProgress = 0

        // Remove all birds
        birds.forEach { $0.removeFromParent() }
        birds.removeAll()

        spawnBirds()
        spawnPipe()
        
//        // [NN] Step 5
//        runTime = 0
//        ai.resetRunState()
    }

    // MARK: Bird spawning
    private func spawnBirds() {
        let birdXScene = frame.minX + frame.width * 0.2
        let baseYScene = frame.midY

        for _ in 0..<birdCount {
            guard let b = birdPrototype.copy() as? SKSpriteNode else {
                fatalError("birdPrototype must be an SKSpriteNode")
            }

            // Match the prototype visuals
            b.size = birdPrototype.size
            b.xScale = birdPrototype.xScale
            b.yScale = birdPrototype.yScale
            b.zPosition = birdPrototype.zPosition

            // Place bird in the world
            b.position = sceneToWorld(CGPoint(x: birdXScene, y: baseYScene))

            // Bird physics must already be configured in the SKS file
            guard let body = b.physicsBody else {
                fatalError("birdPrototype must have a physicsBody set in the Scene Editor")
            }

            // Configure collision rules
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

        let minGapCenter = worldMinY + pipeGap * 0.5
        let maxGapCenter = worldMaxY - pipeGap * 0.5

        let gapYWorld: CGFloat
        if minGapCenter < maxGapCenter {
            gapYWorld = CGFloat.random(in: minGapCenter...maxGapCenter)
        } else {
            gapYWorld = (worldMinY + worldMaxY) * 0.5
        }

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

    // MARK: Input
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        flapAll()
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
        b.alpha = 0
        b.physicsBody?.isDynamic = false
        
//        // [NN] Step 4
//        // Replace bottom if statement with this to allow train/evolve
//        ai.tickAlive(i: idx, distance: runTime)
//        ai.kill(i: idx)
//
//        if birds.allSatisfy({ $0.physicsBody?.isDynamic == false }) {
//            ai.evolveToNextGen()
//            triggerGameOver()
//        }
//        
        // If all birds are dead, trigger restart
        if birds.allSatisfy({ $0.physicsBody?.isDynamic == false }) {
            triggerGameOver()
        }

    }

    private func triggerGameOver() {
        guard !gameOver else { return }
        gameOver = true
        restartAt = lastUpdateTime + 0.6
    }

    // MARK: Game loop
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
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
            if p.x < leftWorld - 120 {
                p.remove()
                return true
            }
            return false
        }

        // Spawn new pipes based on distance traveled
        pipeSpawnProgress += abs(pipeSpeed)
        if pipeSpawnProgress >= spawnDist {
            spawnPipe()
            pipeSpawnProgress = 0
        }

        // Scoring logic:
        // Count when the leading alive bird passes a pipe
        let aliveBirds = birds.filter { $0.physicsBody?.isDynamic == true }
        if let lead = aliveBirds.max(by: { $0.position.x < $1.position.x }) {
            let leadX = lead.position.x
            for p in pipes {
                if !p.passed && p.x + 35 < leadX {
                    p.passed = true
                    score += 1
                    
//                    // [NN] Step 2
//                    // Allow score tracking
//                    for i in birds.indices {
//                        if birds[i].physicsBody?.isDynamic == true {
//                            ai.addScore(i: i)
//                        }
//                    }

                    best = max(best, score)
                    updateHUD()
                }
            }
        }

//        // [NN] Step 3
//        // - compute inputs (birdY, topY, botY, dist, velY, etc.)
//        // - ask your NN if it should flap
//        // - if yes -> set dy to flapVelocityTarget
//        runTime += dt
//
//        let worldMinY = groundNode.frame.maxY
//        let worldMaxY = ceilingNode.frame.minY
//        let h = Double(worldMaxY - worldMinY)
//
//        // choose the next pipe relative to a reference X near bird spawn
//        let refX = sceneXToWorld(frame.minX + frame.width * 0.2)
//        let nextPipe = pipes.first { $0.x + 22 > refX }
//
//        for (i, b) in birds.enumerated() {
//            guard let body = b.physicsBody, body.isDynamic else { continue }
//
//            ai.tickAlive(i: i, distance: runTime)
//
//            let birdY = Double(b.position.y - worldMinY)
//            let velY  = Double(body.velocity.dy)
//
//            let topY: Double
//            let botY: Double
//            let dist: Double
//
//            if let p = nextPipe {
//                topY = Double(p.gapTopY - worldMinY)
//                botY = Double(p.gapBotY - worldMinY)
//                dist = Double(max(0, p.x - b.position.x))
//            } else {
//                topY = h
//                botY = 0
//                dist = 600
//            }
//
//            if ai.shouldFlap(
//                birdIndex: i,
//                birdY: birdY,
//                topY: topY,
//                botY: botY,
//                dist: dist,
//                velY: velY,
//                height: h
//            ) {
//                body.velocity = CGVector(dx: body.velocity.dx, dy: flapVelocityTarget)
//            }
//        }

    }
}
