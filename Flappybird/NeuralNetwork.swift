import Foundation

// MARK: - Simple Neural Network (4 → 8 → 1)
final class NeuralNetwork {

    var w1: [[Double]]   // 8 x 4
    var w2: [Double]     // 8
    var b1: [Double]     // 8
    var b2: Double       // 1

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
        1.0 / (1.0 + exp(-max(-20, min(20, x))))
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

    // MARK: - Simple "learn from parents": average
    static func average(_ a: NeuralNetwork, _ b: NeuralNetwork) -> NeuralNetwork {
        let c = NeuralNetwork(random: false)

        for i in 0..<8 {
            for j in 0..<4 {
                c.w1[i][j] = (a.w1[i][j] + b.w1[i][j]) * 0.5
            }
            c.b1[i] = (a.b1[i] + b.b1[i]) * 0.5
            c.w2[i] = (a.w2[i] + b.w2[i]) * 0.5
        }
        c.b2 = (a.b2 + b.b2) * 0.5
        return c
    }

    // MARK: - Tiny mutation (minimum needed)
    // This is NOT "overcomplicated": it just nudges a few numbers slightly.
    func tinyMutate(chance: Double = 0.03, amount: Double = 0.08) {
        for i in 0..<8 {
            for j in 0..<4 {
                if Double.random(in: 0...1) < chance {
                    w1[i][j] += Double.random(in: -amount...amount)
                }
            }
            if Double.random(in: 0...1) < chance { b1[i] += Double.random(in: -amount...amount) }
            if Double.random(in: 0...1) < chance { w2[i] += Double.random(in: -amount...amount) }
        }
        if Double.random(in: 0...1) < chance { b2 += Double.random(in: -amount...amount) }
    }
}

// MARK: - Genome
final class Genome {
    let brain: NeuralNetwork
    var alive: Bool = true
    var score: Int = 0
    var distance: Double = 0

    init(brain: NeuralNetwork) { self.brain = brain }

    var fitness: Double { Double(score) * 1000 + distance }
}

// MARK: - Flappy AI
final class FlappyAI {

    private let popSize: Int
    private(set) var generation: Int = 1
    private var genomes: [Genome] = []

    init(popSize: Int) {
        self.popSize = popSize
        genomes = (0..<popSize).map { _ in Genome(brain: NeuralNetwork()) }
    }

    func resetRunState() {
        for g in genomes {
            g.alive = true
            g.score = 0
            g.distance = 0
        }
    }

    func tickAlive(i: Int, distance: Double) {
        guard i < genomes.count, genomes[i].alive else { return }
        genomes[i].distance = max(genomes[i].distance, distance)
    }

    func addScore(i: Int) {
        guard i < genomes.count, genomes[i].alive else { return }
        genomes[i].score += 1
    }

    func kill(i: Int) {
        guard i < genomes.count else { return }
        genomes[i].alive = false
    }

    func shouldFlap(birdIndex: Int, birdY: Double, topY: Double, botY: Double, dist: Double, height: Double) -> Bool {
        let g = genomes[birdIndex]
        guard g.alive else { return false }

        let inputs: [Double] = [
            birdY / height,
            topY / height,
            botY / height,
            min(dist, 600) / 600.0
        ]
        return g.brain.predict(inputs) > 0.5
    }

    func evolveToNextGen() {
        genomes.sort { $0.fitness > $1.fitness }

        let eliteCount = max(2, popSize / 10)
        let elites = Array(genomes.prefix(eliteCount))

        var newGen: [Genome] = []

        // 1) keep elites
        for e in elites {
            newGen.append(Genome(brain: e.brain.copy()))
        }

        // 2) children = average of 2 elites + tiny mutation
        while newGen.count < popSize {
            let p1 = elites.randomElement()!
            let p2 = elites.randomElement()!

            let child = NeuralNetwork.average(p1.brain, p2.brain)
            child.tinyMutate(chance: 0.03, amount: 0.08)

            newGen.append(Genome(brain: child))
        }

        genomes = newGen
        generation += 1
        print("=== Generation \(generation) === best fitness \(genomes.first?.fitness ?? 0)")
    }
}
