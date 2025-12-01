//
//  flappybird.swift
//  Flappybird
//
//  Created by Cynthia Zhou on 2025-11-24.
//

import SpriteKit
import GameplayKit
import UIKit

// MARK: - Neural Network
class NeuralNetwork {
    var weights1: [[Double]]
    var weights2: [[Double]]
    var bias1: [Double]
    var bias2: [Double]
    
    init() {
        weights1 = (0..<8).map { _ in (0..<4).map { _ in Double.random(in: -1...1) } }
        weights2 = (0..<1).map { _ in (0..<8).map { _ in Double.random(in: -1...1) } }
        bias1 = (0..<8).map { _ in Double.random(in: -1...1) }
        bias2 = (0..<1).map { _ in Double.random(in: -1...1) }
    }
    
    init(w1: [[Double]], w2: [[Double]], b1: [Double], b2: [Double]) {
        self.weights1 = w1
        self.weights2 = w2
        self.bias1 = b1
        self.bias2 = b2
    }
    
    func sigmoid(_ x: Double) -> Double {
        return 1.0 / (1.0 + exp(-max(-500, min(500, x))))
    }
    
    func predict(inputs: [Double]) -> Double {
        var hidden = [Double](repeating: 0, count: 8)
        for i in 0..<8 {
            var sum = bias1[i]
            for j in 0..<4 {
                sum += inputs[j] * weights1[i][j]
            }
            hidden[i] = sigmoid(sum)
        }
        
        var output = bias2[0]
        for i in 0..<8 {
            output += hidden[i] * weights2[0][i]
        }
        return sigmoid(output)
    }
    
    func copy() -> NeuralNetwork {
        return NeuralNetwork(w1: weights1, w2: weights2, b1: bias1, b2: bias2)
    }
    
    func mutate(rate: Double) {
        for i in 0..<weights1.count {
            for j in 0..<weights1[i].count {
                if Double.random(in: 0...1) < rate {
                    weights1[i][j] += Double.random(in: -0.5...0.5)
                }
            }
        }
        for i in 0..<weights2.count {
            for j in 0..<weights2[i].count {
                if Double.random(in: 0...1) < rate {
                    weights2[i][j] += Double.random(in: -0.5...0.5)
                }
            }
        }
        for i in 0..<bias1.count {
            if Double.random(in: 0...1) < rate {
                bias1[i] += Double.random(in: -0.5...0.5)
            }
        }
        for i in 0..<bias2.count {
            if Double.random(in: 0...1) < rate {
                bias2[i] += Double.random(in: -0.5...0.5)
            }
        }
    }
    
    static func crossover(_ a: NeuralNetwork, _ b: NeuralNetwork) -> NeuralNetwork {
        let child = NeuralNetwork()
        for i in 0..<child.weights1.count {
            for j in 0..<child.weights1[i].count {
                child.weights1[i][j] = Bool.random() ? a.weights1[i][j] : b.weights1[i][j]
            }
        }
        for i in 0..<child.weights2.count {
            for j in 0..<child.weights2[i].count {
                child.weights2[i][j] = Bool.random() ? a.weights2[i][j] : b.weights2[i][j]
            }
        }
        for i in 0..<child.bias1.count {
            child.bias1[i] = Bool.random() ? a.bias1[i] : b.bias1[i]
        }
        for i in 0..<child.bias2.count {
            child.bias2[i] = Bool.random() ? a.bias2[i] : b.bias2[i]
        }
        return child
    }
}

// MARK: - Bird Agent
class BirdAgent {
    var node: SKShapeNode
    var brain: NeuralNetwork
    var alive: Bool = true
    var fitness: Double = 0
    var score: Int = 0
    var distance: Double = 0
    
    init(pos: CGPoint, brain: NeuralNetwork?) {
        node = SKShapeNode(circleOfRadius: 8)
        node.fillColor = UIColor(
            red: CGFloat.random(in: 0.3...1),
            green: CGFloat.random(in: 0.3...1),
            blue: CGFloat.random(in: 0.3...1),
            alpha: 0.7
        )
        node.strokeColor = .white
        node.lineWidth = 1
        node.position = pos
        node.zPosition = 10
        
        self.brain = brain ?? NeuralNetwork()
        
        node.physicsBody = SKPhysicsBody(circleOfRadius: 8)
        node.physicsBody?.isDynamic = true
        node.physicsBody?.allowsRotation = false
        node.physicsBody?.categoryBitMask = 1
        node.physicsBody?.contactTestBitMask = 6
        node.physicsBody?.collisionBitMask = 6
        node.physicsBody?.restitution = 0
    }
    
    func think(birdY: Double, topY: Double, botY: Double, dist: Double, h: Double) {
        guard alive else { return }
        let inputs: [Double] = [
            birdY / h,
            topY / h,
            botY / h,
            min(dist, 400) / 400.0
        ]
        if brain.predict(inputs: inputs) > 0.5 {
            flap()
        }
    }
    
    func flap() {
        node.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
        node.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 4))
    }
    
    func die() {
        alive = false
        node.alpha = 0.15
        node.physicsBody?.isDynamic = false
    }
    
    func calcFitness() {
        fitness = distance + Double(score) * 1000
    }
}

// MARK: - Pipe
class Pipe {
    var top: SKShapeNode
    var bot: SKShapeNode
    var passed = false
    var gapY: CGFloat
    
    var x: CGFloat { return top.position.x }
    var topBottom: CGFloat { return top.position.y - top.frame.height / 2 }
    var botTop: CGFloat { return bot.position.y + bot.frame.height / 2 }
    
    init(xPos: CGFloat, gapY: CGFloat, gap: CGFloat, height: CGFloat) {
        self.gapY = gapY
        let w: CGFloat = 45
        let color = UIColor(red: 0.18, green: 0.55, blue: 0.18, alpha: 1)
        
        let topH = height - gapY - gap / 2
        top = SKShapeNode(rectOf: CGSize(width: w, height: topH))
        top.fillColor = color
        top.strokeColor = UIColor(red: 0.1, green: 0.35, blue: 0.1, alpha: 1)
        top.lineWidth = 2
        top.position = CGPoint(x: xPos, y: gapY + gap / 2 + topH / 2)
        top.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w, height: topH))
        top.physicsBody?.isDynamic = false
        top.physicsBody?.categoryBitMask = 2
        
        let botH = gapY - gap / 2
        bot = SKShapeNode(rectOf: CGSize(width: w, height: botH))
        bot.fillColor = color
        bot.strokeColor = UIColor(red: 0.1, green: 0.35, blue: 0.1, alpha: 1)
        bot.lineWidth = 2
        bot.position = CGPoint(x: xPos, y: botH / 2)
        bot.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w, height: botH))
        bot.physicsBody?.isDynamic = false
        bot.physicsBody?.categoryBitMask = 2
    }
    
    func move(_ dx: CGFloat) {
        top.position.x += dx
        bot.position.x += dx
    }
    
    func remove() {
        top.removeFromParent()
        bot.removeFromParent()
    }
}

// MARK: - Game Scene
class GameScene: SKScene {
    
    let popSize = 100
    var birds: [BirdAgent] = []
    var pipes: [Pipe] = []
    var gen = 1
    var alive = 100
    var best = 0
    var currScore = 0
    var time: Double = 0
    var nextPipe: CGFloat = 150
    
    var genLbl: SKLabelNode!
    var aliveLbl: SKLabelNode!
    var scoreLbl: SKLabelNode!
    var bestLbl: SKLabelNode!
    var speedLbl: SKLabelNode!
    
    let pipeSpeed: CGFloat = -2.5
    let pipeGap: CGFloat = 130
    let spawnDist: CGFloat = 180
    
    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -12)
        backgroundColor = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        
        setupWalls()
        setupLabels()
        spawnGen(brains: nil)
    }
    
    func setupWalls() {
        // Ground
        let ground = SKShapeNode(rectOf: CGSize(width: frame.width, height: 30))
        ground.fillColor = UIColor(red: 0.85, green: 0.7, blue: 0.5, alpha: 1)
        ground.strokeColor = .brown
        ground.position = CGPoint(x: frame.midX, y: 15)
        ground.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: frame.width, height: 30))
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = 4
        addChild(ground)
        
        // Ceiling
        let ceil = SKNode()
        ceil.position = CGPoint(x: frame.midX, y: frame.height)
        ceil.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: frame.width, height: 2))
        ceil.physicsBody?.isDynamic = false
        ceil.physicsBody?.categoryBitMask = 4
        addChild(ceil)
    }
    
    func setupLabels() {
        let fontSize: CGFloat = 16
        
        genLbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        genLbl.fontSize = fontSize
        genLbl.fontColor = .white
        genLbl.horizontalAlignmentMode = .left
        genLbl.position = CGPoint(x: 10, y: frame.height - 50)
        genLbl.zPosition = 100
        addChild(genLbl)
        
        aliveLbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        aliveLbl.fontSize = fontSize
        aliveLbl.fontColor = .white
        aliveLbl.horizontalAlignmentMode = .left
        aliveLbl.position = CGPoint(x: 10, y: frame.height - 70)
        aliveLbl.zPosition = 100
        addChild(aliveLbl)
        
        scoreLbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreLbl.fontSize = fontSize
        scoreLbl.fontColor = .yellow
        scoreLbl.horizontalAlignmentMode = .left
        scoreLbl.position = CGPoint(x: 10, y: frame.height - 90)
        scoreLbl.zPosition = 100
        addChild(scoreLbl)
        
        bestLbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        bestLbl.fontSize = fontSize
        bestLbl.fontColor = .green
        bestLbl.horizontalAlignmentMode = .left
        bestLbl.position = CGPoint(x: 10, y: frame.height - 110)
        bestLbl.zPosition = 100
        addChild(bestLbl)
        
        speedLbl = SKLabelNode(fontNamed: "Arial")
        speedLbl.fontSize = 14
        speedLbl.fontColor = .white
        speedLbl.horizontalAlignmentMode = .right
        speedLbl.position = CGPoint(x: frame.width - 10, y: frame.height - 50)
        speedLbl.zPosition = 100
        speedLbl.text = "Tap: Speed"
        addChild(speedLbl)
        
        updateLabels()
    }
    
    func updateLabels() {
        genLbl.text = "Gen: \(gen)"
        aliveLbl.text = "Alive: \(alive)/\(popSize)"
        scoreLbl.text = "Score: \(currScore)"
        bestLbl.text = "Best: \(best)"
    }
    
    func spawnGen(brains: [NeuralNetwork]?) {
        birds.forEach { $0.node.removeFromParent() }
        birds.removeAll()
        pipes.forEach { $0.remove() }
        pipes.removeAll()
        
        alive = popSize
        currScore = 0
        time = 0
        nextPipe = 150
        
        let startPos = CGPoint(x: frame.width * 0.2, y: frame.midY)
        
        if let parents = brains {
            for i in 0..<popSize {
                let brain: NeuralNetwork
                if i < 5 {
                    brain = parents[i % parents.count].copy()
                } else if i < 25 {
                    brain = parents[i % parents.count].copy()
                    brain.mutate(rate: 0.12)
                } else {
                    let p1 = parents[Int.random(in: 0..<min(10, parents.count))]
                    let p2 = parents[Int.random(in: 0..<min(15, parents.count))]
                    brain = NeuralNetwork.crossover(p1, p2)
                    brain.mutate(rate: 0.18)
                }
                let bird = BirdAgent(pos: startPos, brain: brain)
                birds.append(bird)
                addChild(bird.node)
            }
        } else {
            for _ in 0..<popSize {
                let bird = BirdAgent(pos: startPos, brain: nil)
                birds.append(bird)
                addChild(bird.node)
            }
        }
        updateLabels()
    }
    
    func spawnPipe() {
        let minY = frame.height * 0.22
        let maxY = frame.height * 0.78
        let gapY = CGFloat.random(in: minY...maxY)
        let pipe = Pipe(xPos: frame.width + 30, gapY: gapY, gap: pipeGap, height: frame.height)
        pipes.append(pipe)
        addChild(pipe.top)
        addChild(pipe.bot)
    }
    
    func closestPipe() -> Pipe? {
        let birdX = frame.width * 0.2
        return pipes.first { $0.x + 22 > birdX }
    }
    
    override func update(_ currentTime: TimeInterval) {
        time += 1
        
        // Move pipes
        for p in pipes { p.move(pipeSpeed) }
        
        // Remove old pipes
        pipes.removeAll { p in
            if p.x < -50 { p.remove(); return true }
            return false
        }
        
        // Spawn pipes
        nextPipe += pipeSpeed
        if nextPipe <= 0 {
            spawnPipe()
            nextPipe = spawnDist
        }
        
        // Score
        let birdX = frame.width * 0.2
        for p in pipes {
            if !p.passed && p.x + 22 < birdX {
                p.passed = true
                for b in birds where b.alive {
                    b.score += 1
                    currScore = max(currScore, b.score)
                    best = max(best, b.score)
                }
                updateLabels()
            }
        }
        
        let pipe = closestPipe()
        let h = Double(frame.height)
        
        for b in birds {
            guard b.alive else { continue }
            b.distance = time
            
            let y = b.node.position.y
            if y < 35 || y > frame.height - 5 {
                kill(b)
                continue
            }
            
            if let p = pipe {
                if b.node.frame.intersects(p.top.frame) || b.node.frame.intersects(p.bot.frame) {
                    kill(b)
                    continue
                }
                b.think(birdY: Double(y), topY: Double(p.topBottom), botY: Double(p.botTop), dist: Double(p.x - birdX), h: h)
            } else {
                b.think(birdY: Double(y), topY: h, botY: 0, dist: 400, h: h)
            }
        }
        
        if alive == 0 { nextGen() }
    }
    
    func kill(_ b: BirdAgent) {
        b.die()
        b.calcFitness()
        alive -= 1
        updateLabels()
    }
    
    func nextGen() {
        birds.sort { $0.fitness > $1.fitness }
        let topBrains = birds.prefix(20).map { $0.brain }
        birds.forEach { $0.node.removeFromParent() }
        gen += 1
        spawnGen(brains: Array(topBrains))
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if speed == 1.0 {
            speed = 2.0
            speedLbl.text = "Speed: 2x"
        } else if speed == 2.0 {
            speed = 4.0
            speedLbl.text = "Speed: 4x"
        } else {
            speed = 1.0
            speedLbl.text = "Speed: 1x"
        }
    }
}
