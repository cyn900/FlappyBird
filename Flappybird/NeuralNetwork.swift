import Foundation

// MARK: - Neural Network (4 → 8 → 1)
final class NeuralNetwork {

    // 8 x 4
    var w1: [[Double]]
    // 8
    var w2: [Double]
    // 8
    var b1: [Double]
    // 1
    var b2: Double

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
        // wide clamp to avoid saturation & overflow
        let z = max(-60, min(60, x))
        return 1.0 / (1.0 + exp(-z))
    }

    // inputs must be count=4, normalized
    func predict(_ inputs: [Double]) -> Double {
        var hidden = [Double](repeating: 0, count: 8)

        for i in 0..<8 {
            var sum = b1[i]
            for j in 0..<4 { sum += inputs[j] * w1[i][j] }
            hidden[i] = sigmoid(sum)
        }

        var out = b2
        for i in 0..<8 { out += hidden[i] * w2[i] }
        return sigmoid(out)
    }

    // MARK: - Crossover
    static func crossover(_ a: NeuralNetwork, _ b: NeuralNetwork) -> NeuralNetwork {
        let c = NeuralNetwork(random: false)

        for i in 0..<8 {
            for j in 0..<4 {
                c.w1[i][j] = Bool.random() ? a.w1[i][j] : b.w1[i][j]
            }
            c.w2[i] = Bool.random() ? a.w2[i] : b.w2[i]
            c.b1[i] = Bool.random() ? a.b1[i] : b.b1[i]
        }
        c.b2 = Bool.random() ? a.b2 : b.b2
        return c
    }

    // MARK: - Mutation
    func mutate(rate: Double, amount: Double) {
        for i in 0..<8 {
            for j in 0..<4 {
                if Double.random(in: 0...1) < rate {
                    w1[i][j] += Double.random(in: -amount...amount)
                }
            }
            if Double.random(in: 0...1) < rate { w2[i] += Double.random(in: -amount...amount) }
            if Double.random(in: 0...1) < rate { b1[i] += Double.random(in: -amount...amount) }
        }
        if Double.random(in: 0...1) < rate { b2 += Double.random(in: -amount...amount) }
    }
}

// MARK: - Genome (one brain + run stats)
final class Genome {
    let brain: NeuralNetwork
    var alive: Bool = true
    var score: Int = 0
    var distance: Double = 0

    init(brain: NeuralNetwork) { self.brain = brain }

    // score dominates, distance breaks ties
    var fitness: Double { Double(score) * 1000.0 + distance }
}

// MARK: - Flappy AI (multi-generation evolution with Hall-of-Fame)
final class FlappyAI {

    private let popSize: Int
    private(set) var generation: Int = 1
    private var genomes: [Genome] = []

    // ✅ Real hall-of-fame with fitness stored
    private var hall: [(fitness: Double, brain: NeuralNetwork)] = []
    private var bestEver: (fitness: Double, brain: NeuralNetwork)? = nil
    private let hallSize: Int = 10

    init(popSize: Int) {
        self.popSize = popSize
        self.genomes = (0..<popSize).map { _ in Genome(brain: NeuralNetwork()) }
    }

    // MARK: - Run state
    func resetRunState() {
        for g in genomes {
            g.alive = true
            g.score = 0
            g.distance = 0
        }
    }

    func tickAlive(i: Int, distance: Double) {
        guard i >= 0, i < genomes.count, genomes[i].alive else { return }
        genomes[i].distance = max(genomes[i].distance, distance)
    }

    func addScore(i: Int) {
        guard i >= 0, i < genomes.count, genomes[i].alive else { return }
        genomes[i].score += 1
    }

    func kill(i: Int) {
        guard i >= 0, i < genomes.count else { return }
        genomes[i].alive = false
    }

    // MARK: - Decision
    func shouldFlap(
        birdIndex: Int,
        birdY: Double,
        topY: Double,
        botY: Double,
        dist: Double,
        height: Double,
        velY: Double
    ) -> Bool {
        guard birdIndex >= 0, birdIndex < genomes.count else { return false }
        let g = genomes[birdIndex]
        guard g.alive else { return false }

        let gapCenter = (topY + botY) * 0.5
        let gapSize = max(1.0, topY - botY)
        let relY = (birdY - gapCenter) / gapSize
        let relDist = min(dist, 600) / 600.0
        let normVelY = max(-600.0, min(600.0, velY)) / 600.0
        let normGap = gapSize / height

        let inputs: [Double] = [ relY, relDist, normVelY, normGap ]

        return g.brain.predict(inputs) > 0.55
    }

    // MARK: - Evolution (with guaranteed best protection)
    func evolveToNextGen() {
        // 1) sort by fitness
        genomes.sort { $0.fitness > $1.fitness }

        let prevBest = genomes.first
        let prevBestFitness = prevBest?.fitness ?? 0
        let prevBestScore = prevBest?.score ?? 0
        let prevBestDist  = prevBest?.distance ?? 0

        // MARK: - Update Hall of Fame
        if let best = prevBest {
            let entry = (fitness: best.fitness, brain: best.brain.copy())

            // update best ever
            if bestEver == nil || entry.fitness > bestEver!.fitness {
                bestEver = entry
            }

            // add elites from this generation
            let elites = genomes.prefix(min(20, genomes.count)).map {
                (fitness: $0.fitness, brain: $0.brain.copy())
            }

            hall.append(contentsOf: elites)

            // sort and cap hall
            hall.sort { $0.fitness > $1.fitness }
            if hall.count > hallSize { hall = Array(hall.prefix(hallSize)) }

            // guarantee bestEver is always present
            if let be = bestEver {
                if !hall.contains(where: { abs($0.fitness - be.fitness) < 0.0001 }) {
                    hall.append(be)
                    hall.sort { $0.fitness > $1.fitness }
                    if hall.count > hallSize { hall = Array(hall.prefix(hallSize)) }
                }
            }
        }

        // 2) Parent pool from current generation
        let parentPool = genomes.prefix(min(30, genomes.count)).map { $0.brain }
        if parentPool.isEmpty {
            genomes = (0..<popSize).map { _ in Genome(brain: NeuralNetwork()) }
            generation += 1
            print("=== Gen \(generation) (reset) prevBest=\(prevBestFitness) ===")
            return
        }

        // 3) Build next generation
        var newGen: [Genome] = []
        newGen.reserveCapacity(popSize)

        // ✅ Inject Hall-of-Fame elites first (never lost)
        let hofCount = min(hall.count, max(5, popSize / 10))
        for i in 0..<hofCount {
            newGen.append(Genome(brain: hall[i].brain.copy()))
        }

        // Then inject current generation elites
        let eliteCount = min(max(5, popSize / 10), popSize - newGen.count)
        for i in 0..<eliteCount {
            newGen.append(Genome(brain: parentPool[i % parentPool.count].copy()))
        }

        // Fill rest with mutation & crossover
        while newGen.count < popSize {
            let idx = newGen.count
            let brain: NeuralNetwork

            if idx < min(25, popSize) {
                brain = parentPool[idx % parentPool.count].copy()
                brain.mutate(rate: 0.12, amount: 0.12)
            } else {
                let p1 = parentPool[Int.random(in: 0..<min(10, parentPool.count))]
                let p2 = parentPool[Int.random(in: 0..<min(15, parentPool.count))]
                brain = NeuralNetwork.crossover(p1, p2)
                brain.mutate(rate: 0.18, amount: 0.12)
            }

            newGen.append(Genome(brain: brain))
        }

        genomes = newGen
        generation += 1

        let bestEverFitness = bestEver?.fitness ?? 0
        print("=== Gen \(generation) prevBestFitness=\(prevBestFitness) (score=\(prevBestScore), dist=\(prevBestDist)) bestEver=\(bestEverFitness) ===")
    }
}

