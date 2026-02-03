//
//  Pipe.swift
//  Flappybird
//
//  Created by Cynthia Zhou on 2026-02-03.
//

import SpriteKit
import UIKit

// MARK: - Pipe Wrapper
// This class represents ONE pair of pipes (top + bottom) in the game.
// It is NOT a SpriteKit node itself.
// Instead, it wraps a root SKNode that contains two pipe sprites.
final class Pipe {

    // Root container node that holds both pipe sprites.
    // This lets us move/remove the entire pipe pair together.
    let node: SKNode

    // The visible top and bottom pipe sprites.
    let top: SKSpriteNode
    let bot: SKSpriteNode

    // The Y positions of the top and bottom edges of the gap.
    // These are useful for collision checks or scoring logic.
    let gapTopY: CGFloat
    let gapBotY: CGFloat

    // Whether the bird has already passed this pipe (for scoring).
    var passed = false

    // Convenience property to read the pipe's X position in the world.
    var x: CGFloat { node.position.x }

    // MARK: - Initializer
    // template: a prototype pipe node loaded from GameScene.sks
    // xPosInWorld: where this pipe appears horizontally
    // gapYInWorld: vertical center of the gap
    // gap: vertical size of the gap
    // worldMinY / worldMaxY: bottom and top boundaries of the playable world
    init(
        template: SKNode,
        xPosInWorld: CGFloat,
        gapYInWorld: CGFloat,
        gap: CGFloat,
        worldMinY: CGFloat,
        worldMaxY: CGFloat
    ) {

        // Make a deep copy of the prototype node from the SKS file.
        // Each Pipe instance must be independent.
        guard let copy = template.copy() as? SKNode else {
            fatalError("pipePrototype must be an SKNode")
        }

        self.node = copy

        // Position the pipe pair horizontally in the world.
        // Y stays at 0 because children handle vertical layout.
        self.node.position = CGPoint(x: xPosInWorld, y: 0)

        // Find the top and bottom pipe sprites inside the copied node.
        // These names must match what was set in GameScene.sks.
        guard
            let t = copy.childNode(withName: "//pipeTop") as? SKSpriteNode,
            let b = copy.childNode(withName: "//pipeBottom") as? SKSpriteNode
        else {
            fatalError("pipePrototype must have children named pipeTop and pipeBottom (SKSpriteNode)")
        }

        self.top = t
        self.bot = b

        // Calculate where the gap starts and ends vertically.
        let gapTopY = gapYInWorld + gap * 0.5
        let gapBotY = gapYInWorld - gap * 0.5
        self.gapTopY = gapTopY
        self.gapBotY = gapBotY

        // Resize the pipes so they stretch from the gap
        // all the way to the ceiling and ground.
        let topH = max(10, worldMaxY - gapTopY)
        let botH = max(10, gapBotY - worldMinY)

        top.size.height = topH
        bot.size.height = botH

        // Reposition the pipes so their edges line up with the gap.
        top.position = CGPoint(x: top.position.x, y: gapTopY + topH * 0.5)
        bot.position = CGPoint(x: bot.position.x, y: worldMinY + botH * 0.5)

        // IMPORTANT:
        // We rebuild physics bodies here because we resized the sprites.
        // Physics bodies from the SKS file would no longer match visually.
        top.physicsBody = SKPhysicsBody(rectangleOf: top.size)
        bot.physicsBody = SKPhysicsBody(rectangleOf: bot.size)

        // Configure physics behavior for both pipes.
        // Pipes are static obstacles that never move or bounce.
        for p in [top, bot] {
            p.physicsBody?.isDynamic = false      // Pipes do not respond to forces
            p.physicsBody?.restitution = 0        // No bouncing
            p.physicsBody?.friction = 0           // No sliding interaction

            // Physics category setup:
            // - Pipes belong to the "pipe" category
            // - They collide with the bird
            // - They trigger contact callbacks with the bird
            p.physicsBody?.categoryBitMask = PhysicsCategory.pipe
            p.physicsBody?.contactTestBitMask = PhysicsCategory.bird
            p.physicsBody?.collisionBitMask = PhysicsCategory.bird
        }
    }

    // Move the entire pipe pair horizontally (used for scrolling).
    func move(_ dx: CGFloat) {
        node.position.x += dx
    }

    // Remove the pipe pair from the scene when it goes off-screen.
    func remove() {
        node.removeFromParent()
    }
}
