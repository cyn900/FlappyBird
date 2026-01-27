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

private enum PhysicsCategory {
    static let bird: UInt32    = 1 << 0
    static let pipe: UInt32    = 1 << 1
    static let ground: UInt32  = 1 << 2
    static let ceiling: UInt32 = 1 << 3
}

// MARK: - Pipe Wrapper
final class Pipe {
    let node: SKNode
    let top: SKSpriteNode
    let bot: SKSpriteNode
    let gapTopY: CGFloat
    let gapBotY: CGFloat

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
            fatalError("pipePrototype must have children named pipeTop and pipeBottom (SKSpriteNode)")
        }

        self.top = t
        self.bot = b

        let gapTopY = gapYInWorld + gap * 0.5
        let gapBotY = gapYInWorld - gap * 0.5
        self.gapTopY = gapTopY
        self.gapBotY = gapBotY

        // Resize pipes to fill from ceiling/ground to the gap edges
        let topH = max(10, worldMaxY - gapTopY)
        let botH = max(10, gapBotY - worldMinY)

        top.size.height = topH
        bot.size.height = botH

        top.position = CGPoint(x: top.position.x, y: gapTopY + topH * 0.5)
        bot.position = CGPoint(x: bot.position.x, y: worldMinY + botH * 0.5)

        // Physics bodies (static)
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

// MARK: - Game Scene
final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: Scene nodes from .sks
    private var world: SKNode!
    private var birdPrototype: SKSpriteNode!
    private var pipePrototype: SKNode!
    private var groundNode: SKSpriteNode!
    private var ceilingNode: SKSpriteNode!

    // MARK: Multi-bird
    private var birds: [SKSpriteNode] = []
    private let birdCount = 1

    // MARK: Pipes
    private var pipes: [Pipe] = []
    private var pipeGap: CGFloat = 130
    private let pipeSpeed: CGFloat = -2.5
    private let spawnDist: CGFloat = 280
    private var pipeSpawnProgress: CGFloat = 0

    // MARK: Physics
    private let gravityY: CGFloat = -12
    private var flapVelocityTarget: CGFloat = 320

    // MARK: Timing / state
    private var lastUpdateTime: TimeInterval = 0
    private var didInit = false

    private var gameOver = false
    private var restartAt: TimeInterval? = nil

    // MARK: HUD
    private var scoreLbl: SKLabelNode?
    private var bestLbl: SKLabelNode?
    private var score = 0
    private var best = 0

    // MARK: Setup
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

        guard let pp = childNode(withName: "//pipePrototype") else {
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

        scoreLbl = childNode(withName: "//scoreLabel") as? SKLabelNode
        bestLbl  = childNode(withName: "//bestLabel")  as? SKLabelNode

        pipeGap = computeGapFromPipePrototypeFrames(template: pipePrototype, minGap: 80)
        flapVelocityTarget = computeFlapVelocityTarget()

        resetGame()
    }


    // MARK: Coordinate helpers (Scene <-> World)
    private func sceneToWorld(_ p: CGPoint) -> CGPoint { world.convert(p, from: self) }
    private func sceneXToWorld(_ x: CGFloat) -> CGFloat { sceneToWorld(CGPoint(x: x, y: 0)).x }

    private func computeGapFromPipePrototypeFrames(template: SKNode, minGap: CGFloat) -> CGFloat {
        guard
            let top = template.childNode(withName: "//pipeTop") as? SKSpriteNode,
            let bot = template.childNode(withName: "//pipeBottom") as? SKSpriteNode
        else { return max(130, minGap) }

        let gap = top.frame.minY - bot.frame.maxY
        return max(gap, minGap)
    }

    private func computeFlapVelocityTarget() -> CGFloat {
        // Make flap feel consistent across different sprite sizes / world scales
        let birdHeight = birdPrototype.size.height * birdPrototype.yScale
        let baseline: CGFloat = 16
        let sizeScale = max(0.8, min(2.0, birdHeight / baseline))
        let worldScale = max(0.001, world.yScale)
        return (320 * sizeScale) / worldScale
    }

    // MARK: Reset
    private func resetGame() {
        gameOver = false
        restartAt = nil
        lastUpdateTime = 0

        score = 0
        updateHUD()

        // Clear pipes
        pipes.forEach { $0.remove() }
        pipes.removeAll()
        pipeSpawnProgress = 0

        // Clear birds
        birds.forEach { $0.removeFromParent() }
        birds.removeAll()

        spawnBirds()
        spawnPipe()
    }

    private func spawnBirds() {
        let birdXScene = frame.minX + frame.width * 0.2
        let baseYScene = frame.midY

        for _ in 0..<birdCount {
            guard let b = birdPrototype.copy() as? SKSpriteNode else {
                fatalError("birdPrototype must be an SKSpriteNode")
            }

            // Keep the same visuals as the prototype
            b.size = birdPrototype.size
            b.xScale = birdPrototype.xScale
            b.yScale = birdPrototype.yScale
            b.zPosition = birdPrototype.zPosition

            // Spawn all at same place (simple for workshop)
            b.position = sceneToWorld(CGPoint(x: birdXScene, y: baseYScene))

            // Prototype must have a physics body already set in Scene Editor
            guard let body = b.physicsBody else {
                fatalError("birdPrototype must have a physicsBody set in the Scene Editor")
            }

            body.categoryBitMask = PhysicsCategory.bird
            body.contactTestBitMask = PhysicsCategory.pipe | PhysicsCategory.ground | PhysicsCategory.ceiling
            body.collisionBitMask = PhysicsCategory.pipe | PhysicsCategory.ground | PhysicsCategory.ceiling

            birds.append(b)
            world.addChild(b)
        }
    }

    private func updateHUD() {
        scoreLbl?.text = "Current: \(score)"
        bestLbl?.text = "Best: \(best)"
    }

    // MARK: Pipes
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

    // MARK: Input (manual)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        flapAll()
    }

    private func flapAll() {
        for b in birds {
            guard let body = b.physicsBody, body.isDynamic else { continue }
            body.velocity = CGVector(dx: body.velocity.dx, dy: flapVelocityTarget)
        }
    }

    // MARK: Collision
    func didBegin(_ contact: SKPhysicsContact) {
        let birdBody: SKPhysicsBody?
        if contact.bodyA.categoryBitMask == PhysicsCategory.bird { birdBody = contact.bodyA }
        else if contact.bodyB.categoryBitMask == PhysicsCategory.bird { birdBody = contact.bodyB }
        else { birdBody = nil }

        guard let bBody = birdBody, let node = bBody.node as? SKSpriteNode else { return }
        killBird(node)
    }

    private func killBird(_ bird: SKSpriteNode) {
        guard let idx = birds.firstIndex(where: { $0 === bird }) else { return }
        let b = birds[idx]
        b.alpha = 0
        b.physicsBody?.isDynamic = false

        // If all birds are dead -> auto restart
        if birds.allSatisfy({ $0.physicsBody?.isDynamic == false }) {
            triggerGameOver()
        }
    }

    private func triggerGameOver() {
        guard !gameOver else { return }
        gameOver = true
        restartAt = lastUpdateTime + 0.6
    }

    // MARK: Update loop
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime == 0 { dt = 1.0 / 60.0 }
        else { dt = currentTime - lastUpdateTime }
        lastUpdateTime = currentTime

        // Auto restart
        if gameOver {
            if let t = restartAt, currentTime >= t {
                resetGame()
            }
            return
        }

        // Move pipes
        for p in pipes { p.move(pipeSpeed) }

        // Remove off-screen pipes
        let leftWorld = sceneXToWorld(frame.minX)
        pipes.removeAll { p in
            if p.x < leftWorld - 120 {
                p.remove()
                return true
            }
            return false
        }

        // Spawn new pipes
        pipeSpawnProgress += abs(pipeSpeed)
        if pipeSpawnProgress >= spawnDist {
            spawnPipe()
            pipeSpawnProgress = 0
        }

        // Score: count when the leading alive bird passes a pipe
        let aliveBirds = birds.filter { $0.physicsBody?.isDynamic == true }
        if let lead = aliveBirds.max(by: { $0.position.x < $1.position.x }) {
            let leadX = lead.position.x
            for p in pipes {
                if !p.passed && p.x + 35 < leadX {
                    p.passed = true
                    score += 1
                    best = max(best, score)
                    updateHUD()
                }
            }
        }

        // [NN STEP] Later in the workshop, you’ll add:
        // - compute inputs (birdY, topY, botY, dist, velY, etc.)
        // - ask your NN if it should flap
        // - if yes -> set dy to flapVelocityTarget
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
//            // Optional fitness tick
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
