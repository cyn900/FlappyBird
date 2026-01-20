import Foundation
import UIKit

// MARK: - Simple Neural Network (4 → 8 → 1)

final class NeuralNetwork {

    var w1: [[Double]]   // 8 x 4
    var w2: [Double]    // 1 x 8
    var b1: [Double]   // 8
    var b2: Double     // 1

    init(random: Bool = true) {
        if random {
            w1 = (0..<8).map { _ in (0..<4).map { _ in Double.random(in: -1...1) } }
            w2 = (0..<8).map { _ in Double.random(in: -1...1) }
            b1 = (0..<8).map { _ in Double.random(in: -1...1) }
            b2 = Double.random(in: -1...1)
        } else {
            w1 = Array(repeating: Array(repeating: 0, count: 4), count: 8)
            w2 = Array(repeating: 0, count: 8)
            b1 = Array(repeating: 0, count: 8)
            b2 = 0
        }
    }

    func copy() -> NeuralNetwork {
        let n = NeuralNetwork(random: false)
        n.w1 = w1
        n.w2 = w2
        n.b1 = b1
        n.b2 = b2
        return n
    }

    private func sigmoid(_ x: Double) -> Double {
        return 1.0 / (1.0 + exp(-max(-20, min(20, x))))
    }

    // inputs = [birdY, topY, botY, dist] normalized
    func predict(_ inputs: [Double]) -> Double {
        var hidden = [Double](repeating: 0, count: 8)

        for i in 0..<8 {
            var sum = b1[i]
            for j in 0..<4 {
                sum += inputs[j] * w1[i][j]
            }
            hidden[i] = sigmoid(sum)
        }

        var out = b2
        for i in 0..<8 {
            out += hidden[i] * w2[i]
        }

        return sigmoid(out)
    }

    func mutate(rate: Double) {
        for i in 0..<8 {
            for j in 0..<4 {
                if Double.random(in: 0...1) < rate {
                    w1[i][j] += Double.random(in: -0.4...0.4)
                }
            }
            if Double.random(in: 0...1) < rate {
                b1[i] += Double.random(in: -0.4...0.4)
            }
            if Double.random(in: 0...1) < rate {
                w2[i] += Double.random(in: -0.4...0.4)
            }
        }

        if Double.random(in: 0...1) < rate {
            b2 += Double.random(in: -0.4...0.4)
        }
    }

    static func crossover(_ a: NeuralNetwork, _ b: NeuralNetwork) -> NeuralNetwork {
        let c = NeuralNetwork(random: false)

        for i in 0..<8 {
            for j in 0..<4 {
                c.w1[i][j] = Bool.random() ? a.w1[i][j] : b.w1[i][j]
            }
            c.b1[i] = Bool.random() ? a.b1[i] : b.b1[i]
            c.w2[i] = Bool.random() ? a.w2[i] : b.w2[i]
        }

        c.b2 = Bool.random() ? a.b2 : b.b2
        return c
    }
}






// MARK: - Genome (one bird brain + stats)

final class Genome {
    let brain: NeuralNetwork
    var alive: Bool = true
    var score: Int = 0
    var distance: Double = 0

    init(brain: NeuralNetwork) {
        self.brain = brain
    }

    var fitness: Double {
        // score dominates, distance breaks ties
        return Double(score) * 1000 + distance
    }
}






// MARK: - Flappy AI (Genetic Algorithm Manager)

final class FlappyAI {

    private let popSize: Int
    private(set) var generation: Int = 1

    private var genomes: [Genome] = []

    init(popSize: Int) {
        self.popSize = popSize
        createInitialPopulation()
    }

    private func createInitialPopulation() {
        genomes = (0..<popSize).map { _ in
            Genome(brain: NeuralNetwork())
        }
    }

    // MARK: - Run control (called by GameScene)

    func currentSpawnPack() -> [NeuralNetwork] {
        return genomes.map { ($0.brain) }
    }

    func resetRunState() {
        for g in genomes {
            g.alive = true
            g.score = 0
            g.distance = 0
        }
    }

    func tickAlive(i: Int, distance: Double) {
        guard i < genomes.count else { return }
        if genomes[i].alive {
            genomes[i].distance = max(genomes[i].distance, distance)
        }
    }

    func addScore(i: Int) {
        guard i < genomes.count else { return }
        if genomes[i].alive {
            genomes[i].score += 1
        }
    }

    func kill(i: Int) {
        guard i < genomes.count else { return }
        genomes[i].alive = false
    }

    // MARK: - Decision

    func shouldFlap(
        birdIndex: Int,
        birdY: Double,
        topY: Double,
        botY: Double,
        dist: Double,
        height: Double
    ) -> Bool {

        let g = genomes[birdIndex]
        guard g.alive else { return false }

        // normalize inputs to ~0–1 range
        let inputs: [Double] = [
            birdY / height,
            topY / height,
            botY / height,
            min(dist, 600) / 600.0
        ]

        let out = g.brain.predict(inputs)

        // flap threshold (tune this!)
        return out > 0.5
    }

    // MARK: - Evolution

    func evolveToNextGen() {
        // sort by fitness descending
        genomes.sort { $0.fitness > $1.fitness }

        let eliteCount = max(2, popSize / 10)
        let elites = Array(genomes.prefix(eliteCount))

        var newGen: [Genome] = []

        // keep elites unchanged
        for e in elites {
            newGen.append(Genome(brain: e.brain.copy()))
        }

        // fill rest by crossover + mutation
        while newGen.count < popSize {
            let p1 = elites.randomElement()!
            let p2 = elites.randomElement()!

            let childBrain = NeuralNetwork.crossover(p1.brain, p2.brain)
            childBrain.mutate(rate: 0.15)

            newGen.append(Genome(brain: childBrain))
        }

        genomes = newGen
        generation += 1

        print("=== Generation \(generation) ===")
    }
}
