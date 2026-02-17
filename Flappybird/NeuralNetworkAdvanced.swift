//
//  AdvancedFlappyAI.swift
//  Flappybird
//
//  Advanced version of AI with GA + NN
//

import Foundation
import UIKit


protocol FlappyAIProtocol {
    func evolve()
    func shouldFlap(birdIndex: Int, birdY: Double, topY: Double, botY: Double, dist: Double,velY: Double?, height: Double) -> Bool
    func tickAlive(i: Int, distance: Double)
    func addScore(i: Int)
    func kill(i: Int)
    func resetRunState()
}

// MARK: - Neural Network (4 → 8 → 1)
final class NeuralNetworkAdvanced {

    var w1: [[Double]] = []
    var w2: [Double] = []
    var b1: [Double] = []
    var b2: Double = 0

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

    func copy() -> NeuralNetworkAdvanced {
        let n = NeuralNetworkAdvanced(random: false)
        n.w1 = w1
        n.w2 = w2
        n.b1 = b1
        n.b2 = b2
        return n
    }

    private func relu(_ x: Double) -> Double { max(0, x) }

    private func sigmoid(_ x: Double) -> Double {
        let z = max(-60, min(60, x))
        return 1 / (1 + exp(-z))
    }

    func predict(_ inputs: [Double]) -> Double {
        precondition(inputs.count == 4)
        var hidden = [Double](repeating: 0, count: 8)
        for i in 0..<8 {
            var sum = b1[i]
            for j in 0..<4 { sum += inputs[j] * w1[i][j] }
            hidden[i] = relu(sum)
        }
        var out = b2
        for i in 0..<8 { out += hidden[i] * w2[i] }
        return sigmoid(out)
    }

    func clipAll(to limit: Double = 6.0) {
        for i in 0..<8 {
            for j in 0..<4 { w1[i][j] = min(max(w1[i][j], -limit), limit) }
            w2[i] = min(max(w2[i], -limit), limit)
            b1[i] = min(max(b1[i], -limit), limit)
        }
        b2 = min(max(b2, -limit), limit)
    }

    func mutate(rate: Double, step: Double) {
        for i in 0..<8 {
            for j in 0..<4 { if Double.random(in: 0...1) < rate { w1[i][j] += Double.random(in: -step...step) } }
            if Double.random(in: 0...1) < rate { b1[i] += Double.random(in: -step...step) }
            if Double.random(in: 0...1) < rate { w2[i] += Double.random(in: -step...step) }
        }
        if Double.random(in: 0...1) < rate { b2 += Double.random(in: -step...step) }
        clipAll()
    }

    static func crossover(_ a: NeuralNetworkAdvanced, _ b: NeuralNetworkAdvanced) -> NeuralNetworkAdvanced {
        let c = NeuralNetworkAdvanced(random: false)
        for i in 0..<8 {
            for j in 0..<4 { c.w1[i][j] = Bool.random() ? a.w1[i][j] : b.w1[i][j] }
            c.b1[i] = Bool.random() ? a.b1[i] : b.b1[i]
            c.w2[i] = Bool.random() ? a.w2[i] : b.w2[i]
        }
        c.b2 = Bool.random() ? a.b2 : b.b2
        c.clipAll()
        return c
    }
}

// MARK: - GenomeAdvanced
final class GenomeAdvanced {
    let brain: NeuralNetworkAdvanced
    var alive: Bool = true
    var score: Int = 0
    var distance: Double = 0
    let color: UIColor = UIColor(
        hue: CGFloat.random(in: 0...1),
        saturation: 0.8,
        brightness: 0.9,
        alpha: 1
    )

    init(brain: NeuralNetworkAdvanced) { self.brain = brain }

    var fitness: Double { Double(score) * 1000 + distance }
}

// MARK: - AdvancedFlappyAI
final class AdvancedFlappyAI : FlappyAIProtocol {

    private let popSize: Int
    private(set) var generation: Int = 1
    private var genomes: [GenomeAdvanced] = []

    // Champion preservation
    private var championBrain: NeuralNetworkAdvanced?
    private var championScore: Int = 0
    private var championFitness: Double = -Double.infinity

    // GA knobs
    private var eliteFraction: Double = 0.2
    private var tournamentK: Int = 5
    private var baseMutationRate: Double = 0.18
    private var minMutationRate: Double = 0.05
    private var baseMutationStep: Double = 0.45
    private var minMutationStep: Double = 0.10

    // Flap policy
    var useStochasticPolicy: Bool = false
    var flapThreshold: Double = 0.5

    init(popSize: Int) {
        self.popSize = popSize
        genomes = (0..<popSize).map { _ in GenomeAdvanced(brain: NeuralNetworkAdvanced()) }
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

    func shouldFlap(
        birdIndex: Int,
        birdY: Double,
        topY: Double,
        botY: Double,
        dist: Double,
        velY: Double?,
        height: Double
    ) -> Bool {
        let g = genomes[birdIndex]
        guard g.alive else { return false }

        let gapCenter = (topY + botY) * 0.5
        let gapHalf = max(1e-6, (topY - botY) * 0.5)
        let yRel = (birdY - gapCenter) / gapHalf
        let velN = max(-1, min(1, (velY ?? 0) / 400))
        let distN = min(max(dist, 0), 200) / 200
        let gapN = gapHalf / max(1e-6, height)

        let inputs: [Double] = [yRel, velN, distN, gapN]
        let out = g.brain.predict(inputs)
        return useStochasticPolicy ? out > Double.random(in: 0...1) : out > flapThreshold
    }

    private func tournamentPick(from pool: [GenomeAdvanced]) -> GenomeAdvanced {
        let k = max(2, min(tournamentK, pool.count))
        var best = pool[Int.random(in: 0..<pool.count)]
        for _ in 1..<k {
            let c = pool[Int.random(in: 0..<pool.count)]
            if c.fitness > best.fitness { best = c }
        }
        return best
    }

    func evolve() {
        genomes.sort { $0.fitness > $1.fitness }

        if let bestNow = genomes.first, bestNow.fitness > championFitness {
            championFitness = bestNow.fitness
            championScore = bestNow.score
            championBrain = bestNow.brain.copy()
        }

        let eliteCount = max(2, Int(Double(popSize) * eliteFraction))
        let elites = Array(genomes.prefix(eliteCount))

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

        var newGen: [GenomeAdvanced] = []
        newGen.reserveCapacity(popSize)

        if let champ = championBrain { newGen.append(GenomeAdvanced(brain: champ.copy())) }
        for e in elites { if newGen.count < eliteCount { newGen.append(GenomeAdvanced(brain: e.brain.copy())) } }

        while newGen.count < popSize {
            let p1 = tournamentPick(from: elites)
            let p2 = tournamentPick(from: elites)
            let child = NeuralNetworkAdvanced.crossover(p1.brain, p2.brain)
            child.mutate(rate: rate, step: step)
            newGen.append(GenomeAdvanced(brain: child))
        }

        genomes = newGen
        generation += 1

        print("=== Generation \(generation) === bestScore(gen)=\(bestScore) | championScore=\(championScore) | rate=\(String(format: "%.3f", rate)) step=\(String(format: "%.3f", step))")
    }

    func currentSpawnPack() -> [(brain: NeuralNetworkAdvanced, color: UIColor)] {
        genomes.map { ($0.brain, $0.color) }
    }
}
