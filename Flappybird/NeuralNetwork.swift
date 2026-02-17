
import Foundation  // basic tools needed

// MARK: - Global Switch
struct AIConfig {
    static var advanced: Bool = false // use advanced mode
}

// MARK: - Simple Neural Network (4 → 8 → 1)
final class NeuralNetwork {

    var w1: [[Double]]   // importance of each input to hidden neurons
    var w2: [Double]     // importance of hidden neurons to output
    var b1: [Double]     // hidden layer adjustment (bias)
    var b2: Double       // output adjustment (bias)

    init(random: Bool = true) {
        if random {
            // assign random importance so brains start differently
            w1 = (0..<8).map { _ in (0..<4).map { _ in Double.random(in: -1...1) } }
            w2 = (0..<8).map { _ in Double.random(in: -1...1) }
            b1 = (0..<8).map { _ in Double.random(in: -1...1) }
            b2 = Double.random(in: -1...1)
        } else {
            // create brain with zeroed values
            w1 = Array(repeating: Array(repeating: 0, count: 4), count: 8)
            w2 = Array(repeating: 0, count: 8)
            b1 = Array(repeating: 0, count: 8)
            b2 = 0
        }
    }

    func copy() -> NeuralNetwork {
        let n = NeuralNetwork(random: false) // new brain container
        n.w1 = w1  // copy all input importance
        n.w2 = w2  // copy hidden importance
        n.b1 = b1  // copy hidden bias
        n.b2 = b2  // copy output bias
        return n // return exact copy of brain
    }

    private func sigmoid(_ x: Double) -> Double {
        // logic: converts any number into 0-1 chance
        1.0 / (1.0 + exp(-max(-20, min(20, x))))
    }

    // calculate brain's decision based on input facts
    func predict(_ inputs: [Double]) -> Double {
        var hidden = [Double](repeating: 0, count: 8) // store hidden neuron outputs

        // compute each hidden neuron
        for i in 0..<8 {
            var sum = b1[i] // start with bias (adjustment)
            for j in 0..<4 {
                sum += inputs[j] * w1[i][j] // each fact × importance
            }
            hidden[i] = sigmoid(sum) // filter result to 0-1
        }

        // compute output neuron
        var out = b2 // start with output bias
        for i in 0..<8 {
            out += hidden[i] * w2[i] // combine all hidden outputs
        }

        return sigmoid(out) // final probability to flap
    }

    // combine two parent brains into a child
    static func average(_ a: NeuralNetwork, _ b: NeuralNetwork) -> NeuralNetwork {
        let c = NeuralNetwork(random: false) // new child brain

        for i in 0..<8 {
            for j in 0..<4 {
                // logic: mix parent input importance
                c.w1[i][j] = (a.w1[i][j] + b.w1[i][j]) * 0.5
            }
            // logic: mix biases so child is similar to parents
            c.b1[i] = (a.b1[i] + b.b1[i]) * 0.5
            c.w2[i] = (a.w2[i] + b.w2[i]) * 0.5
        }
        c.b2 = (a.b2 + b.b2) * 0.5 // mix output bias
        return c // child brain ready
    }

    // make small random changes to explore new ideas
    func tinyMutate(chance: Double = 0.03, amount: Double = 0.08) {
        for i in 0..<8 {
            for j in 0..<4 {
                if Double.random(in: 0...1) < chance {
                    w1[i][j] += Double.random(in: -amount...amount) // small input change
                }
            }
            if Double.random(in: 0...1) < chance { b1[i] += Double.random(in: -amount...amount) } // small hidden bias change
            if Double.random(in: 0...1) < chance { w2[i] += Double.random(in: -amount...amount) } // small hidden-output change
        }
        if Double.random(in: 0...1) < chance { b2 += Double.random(in: -amount...amount) } // small output bias change
    }
}

// MARK: - Genome
final class Genome {
    let brain: NeuralNetwork // brain of this bird
    var alive: Bool = true   // is it still flying?
    var score: Int = 0       // pipes passed
    var distance: Double = 0 // how far it traveled

    init(brain: NeuralNetwork) { self.brain = brain } // assign brain

    var fitness: Double { Double(score) * 1000 + distance }
    // logic: combines score and distance into one "how good" number
}

// MARK: - Flappy AI
final class FlappyAI: FlappyAIProtocol {

    private let popSize: Int // number of birds per generation
    private(set) var generation: Int = 1 // which generation
    private var genomes: [Genome] = [] // all birds

    init(popSize: Int) {
        self.popSize = popSize
        // create initial population with random brains
        genomes = (0..<popSize).map { _ in Genome(brain: NeuralNetwork()) }
    }

    // reset game for all birds
    func resetRunState() {
        for g in genomes {
            g.alive = true // revive
            g.score = 0    // reset points
            g.distance = 0 // reset distance
        }
    }

    // update bird's distance
    func tickAlive(i: Int, distance: Double) {
        guard i < genomes.count, genomes[i].alive else { return } // ignore dead
        genomes[i].distance = max(genomes[i].distance, distance) // keep best distance
    }

    // add score for passing a pipe
    func addScore(i: Int) {
        guard i < genomes.count, genomes[i].alive else { return }
        genomes[i].score += 1 // increase points
    }

    // mark bird as dead
    func kill(i: Int) {
        guard i < genomes.count else { return }
        genomes[i].alive = false // stop updating
    }

    // ask brain if bird should flap
    func shouldFlap(birdIndex: Int, birdY: Double, topY: Double, botY: Double, dist: Double,velY: Double?, height: Double) -> Bool {
        let g = genomes[birdIndex]
        guard g.alive else { return false } // dead birds don't flap

        // convert game state into normalized facts
        let inputs: [Double] = [
            birdY / height,       // bird height
            topY / height,        // top pipe
            botY / height,        // bottom pipe
            min(dist, 600) / 600.0 // distance to next pipe
        ]
        return g.brain.predict(inputs) > 0.5 // logic: flap if brain says yes
    }
    
   func evolve() {
       evolveToNextGen()
   }

    // evolve population to next generation
    func evolveToNextGen() {
        genomes.sort { $0.fitness > $1.fitness } // rank birds by fitness
        let bestFitness = genomes.first?.fitness ?? 0
        print("=== Generation \(generation) === best fitness \(bestFitness)")

        let eliteCount = max(2, popSize / 10) // keep top 10% as parents
        let elites = Array(genomes.prefix(eliteCount))

        var newGen: [Genome] = [] // new population

        // 1) keep elites exactly
        for e in elites {
            newGen.append(Genome(brain: e.brain.copy())) // best birds survive unchanged
        }

        // 2) create children
        while newGen.count < popSize {
            let p1 = elites.randomElement()! // parent 1
            let p2 = elites.randomElement()! // parent 2

            let child = NeuralNetwork.average(p1.brain, p2.brain) // combine traits
            child.tinyMutate(chance: 0.03, amount: 0.08) // slight variation

            newGen.append(Genome(brain: child)) // add to population
        }

        genomes = newGen // replace old population
        generation += 1 // increment generation counter
    }
}
