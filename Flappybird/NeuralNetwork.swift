//
//  FlappyAI.swift
//  Flappybird
//
//  GA + NN for SpriteKit (.sks) version (stabilized learning)
//
//  Key fixes:
//  - Champion preservation: best brain is never lost
//  - Deterministic policy by default (removes evaluation noise)
//  - Mutation annealing (explore early, refine later)
//  - Tournament selection (stronger parent selection pressure)
//  - Weight/bias clipping to avoid drift/explosions
//

import Foundation
import UIKit

// MARK: - Simple Neural Network (4 → 8 → 1)

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

    private func relu(_ x: Double) -> Double { max(0.0, x) }

    private func sigmoid(_ x: Double) -> Double {
        let z = max(-60.0, min(60.0, x))
        return 1.0 / (1.0 + exp(-z))
    }

    // inputs = 4 normalized features
    func predict(_ inputs: [Double]) -> Double {
        precondition(inputs.count == 4, "NeuralNetwork expects exactly 4 inputs")

        var hidden = [Double](repeating: 0, count: 8)

        for i in 0..<8 {
            var sum = b1[i]
            for j in 0..<4 { sum += inputs[j] * w1[i][j] }
            hidden[i] = relu(sum)
        }

        var out = b2
        for i in 0..<8 { out += hidden[i] * w2[i] }

        return sigmoid(out) // 0..1
    }

    // Small helper to prevent weights drifting too far
    private func clip(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, x))
    }

    func clipAll(to limit: Double = 6.0) {
        for i in 0..<8 {
            for j in 0..<4 { w1[i][j] = clip(w1[i][j], -limit, limit) }
            w2[i] = clip(w2[i], -limit, limit)
            b1[i] = clip(b1[i], -limit, limit)
        }
        b2 = clip(b2, -limit, limit)
    }

    func mutate(rate: Double, step: Double) {
        // step controls mutation magnitude (annealed by FlappyAI)
        for i in 0..<8 {
            for j in 0..<4 {
                if Double.random(in: 0...1) < rate {
                    w1[i][j] += Double.random(in: -step...step)
                }
            }
            if Double.random(in: 0...1) < rate { b1[i] += Double.random(in: -step...step) }
            if Double.random(in: 0...1) < rate { w2[i] += Double.random(in: -step...step) }
        }
        if Double.random(in: 0...1) < rate { b2 += Double.random(in: -step...step) }

        clipAll(to: 6.0)
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
        c.clipAll(to: 6.0)
        return c
    }
}

// MARK: - Genome

final class Genome {
    let brain: NeuralNetwork
    var alive: Bool = true
    var score: Int = 0
    var distance: Double = 0
    let color: UIColor

    init(brain: NeuralNetwork) {
        self.brain = brain
        self.color = UIColor(
            hue: CGFloat.random(in: 0...1),
            saturation: 0.8,
            brightness: 0.9,
            alpha: 1.0
        )
    }

    var fitness: Double {
        // score dominates, distance breaks ties
        Double(score) * 1000.0 + distance
    }
}

// MARK: - FlappyAI

final class FlappyAI {

    private let popSize: Int
    private(set) var generation: Int = 1
    private var genomes: [Genome] = []

    // Deterministic policy by default (stable learning curve)
    var useStochasticPolicy: Bool = false
    var flapThreshold: Double = 0.5

    // GA knobs
    var eliteFraction: Double = 0.20          // more stable than 0.10
    var tournamentK: Int = 5                 // tournament size
    var baseMutationRate: Double = 0.18      // will anneal down
    var minMutationRate: Double = 0.05
    var baseMutationStep: Double = 0.45      // will anneal down
    var minMutationStep: Double = 0.10

    // Champion (best-ever brain) is preserved across generations
    private var championBrain: NeuralNetwork?
    private var championScore: Int = 0
    private var championFitness: Double = -Double.infinity

    init(popSize: Int) {
        self.popSize = popSize
        genomes = (0..<popSize).map { _ in Genome(brain: NeuralNetwork()) }
    }

    // MARK: - Run control

    func currentSpawnPack() -> [(brain: NeuralNetwork, color: UIColor)] {
        genomes.map { ($0.brain, $0.color) }
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
        if genomes[i].alive { genomes[i].score += 1 }
    }

    func kill(i: Int) {
        guard i < genomes.count else { return }
        genomes[i].alive = false
    }

    // MARK: - Decision (gap-centered normalization)

    func shouldFlap(
        birdIndex: Int,
        birdY: Double,
        topY: Double,
        botY: Double,
        dist: Double,
        velY: Double,
        height: Double
    ) -> Bool {

        let g = genomes[birdIndex]
        guard g.alive else { return false }

        let gapCenter = (topY + botY) * 0.5
        let gapHalf = max(1e-6, (topY - botY) * 0.5)

        // y relative to gap center, scaled by half-gap (≈ -1..1)
        let yRel = (birdY - gapCenter) / gapHalf

        // vertical velocity normalized (≈ -1..1)
        let velN = max(-1.0, min(1.0, velY / 400.0))

        // distance to pipe normalized (0..1), cap at 200 (more relevant)
        let distN = min(max(dist, 0.0), 200.0) / 200.0

        // gap size relative to playable height
        let gapN = gapHalf / max(1e-6, height)

        let inputs: [Double] = [yRel, velN, distN, gapN]
        let out = g.brain.predict(inputs) // 0..1

        if useStochasticPolicy {
            return out > Double.random(in: 0...1)
        } else {
            return out > flapThreshold
        }
    }

    // MARK: - Evolution

    private func tournamentPick(from pool: [Genome]) -> Genome {
        let k = max(2, min(tournamentK, pool.count))
        var best = pool[Int.random(in: 0..<pool.count)]
        for _ in 1..<k {
            let c = pool[Int.random(in: 0..<pool.count)]
            if c.fitness > best.fitness { best = c }
        }
        return best
    }

    func evolveToNextGen() {
        // Sort by fitness descending
        genomes.sort { $0.fitness > $1.fitness }

        // Track best of THIS generation (for logging + champion)
        if let bestNow = genomes.first {
            if bestNow.fitness > championFitness {
                championFitness = bestNow.fitness
                championScore = bestNow.score
                championBrain = bestNow.brain.copy()
            }
        }

        // Elites (carry forward)
        let eliteCount = max(2, Int(Double(popSize) * eliteFraction))
        let elites = Array(genomes.prefix(eliteCount))

        // Anneal mutation based on current best score (simple + effective)
        let bestScore = elites.first?.score ?? 0
        let rate: Double
        let step: Double
        if bestScore < 5 {
            rate = baseMutationRate
            step = baseMutationStep
        } else if bestScore < 12 {
            rate = max(minMutationRate, 0.12)
            step = max(minMutationStep, 0.25)
        } else {
            rate = max(minMutationRate, 0.06)
            step = max(minMutationStep, 0.15)
        }

        var newGen: [Genome] = []
        newGen.reserveCapacity(popSize)

        // 1) Champion slot (best-ever) first, always
        if let champ = championBrain {
            newGen.append(Genome(brain: champ.copy()))
        }

        // 2) Fill the rest of the elite slots with current elites (unaltered)
        for e in elites {
            if newGen.count >= eliteCount { break }
            newGen.append(Genome(brain: e.brain.copy()))
        }

        // 3) Create children until popSize using tournament selection from elites
        while newGen.count < popSize {
            let p1 = tournamentPick(from: elites)
            let p2 = tournamentPick(from: elites)

            let child = NeuralNetwork.crossover(p1.brain, p2.brain)
            child.mutate(rate: rate, step: step)
            newGen.append(Genome(brain: child))
        }

        genomes = newGen
        generation += 1

        // Log using champion + best of previous generation
        print("=== Generation \(generation) === bestScore(gen)=\(bestScore) | championScore=\(championScore) | mutRate=\(String(format: "%.3f", rate)) step=\(String(format: "%.3f", step))")
    }
}
