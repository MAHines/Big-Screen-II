//
//  FocusBoxView.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 3/1/20.
//  Copyright © 2020 Hines Lab. All rights reserved.
//

import Foundation
import UIKit
final class FocusBoxView: UIView {
    
    // MARK: - Instantiation
    private var size: CGFloat = 7.0
    private var lineLen: CGFloat = 10 * 7.0
    private var sunCtr: CGFloat = 0.0
    private var lineX:CGFloat = 63
    private var lineY:CGFloat = 25
    let focusBoxLayer = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        
        backgroundColor = .clear
        focusBoxLayer.opacity = 0
        focusBoxLayer.fillColor = nil
        focusBoxLayer.strokeColor = UIColor.yellow.cgColor

        setupLayer()
        layer.addSublayer(focusBoxLayer)
    }
    
    // MARK: - API
    
    /// This zooms/fades in a focus square and blinks it a few times, then slowly fades it out
    func setCtr(ctr: Float) {
        sunCtr = CGFloat(ctr)
        //setupLayer()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.focusBoxLayer.removeAllAnimations()
        self.changeShape()
    }
    
    func showBox() {
        focusBoxLayer.removeAllAnimations()
        focusBoxLayer.opacity = 1.0
    }
    func vanishBox() {
        focusBoxLayer.removeAllAnimations()
        focusBoxLayer.opacity = 0.0
    }
    func hideBox() {
        focusBoxLayer.removeAllAnimations()
        
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 3.0
        animation.isRemovedOnCompletion = false
        //animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
        animation.delegate = self
        animation.fillMode = .forwards
                
        self.focusBoxLayer.add(animation, forKey: "path")

    }
    func showBox(at point: CGPoint) {
        focusBoxLayer.removeAllAnimations()
        let fadeInKey = "fade in focus box"
        let pulseKey = "pulse focus box"
        let fadeOutKey = "fade out focus box"
        guard focusBoxLayer.animation(forKey: fadeInKey) == nil,
            focusBoxLayer.animation(forKey: pulseKey) == nil,
            focusBoxLayer.animation(forKey: fadeOutKey) == nil
            else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let newPoint = CGPoint(x: point.x, y: point.y)
        focusBoxLayer.position = newPoint
        CATransaction.commit()

        let opacityFadeIn = CABasicAnimation(keyPath: "opacity")
        opacityFadeIn.fromValue = 0
        opacityFadeIn.toValue = 1
        opacityFadeIn.duration = 0.3
        opacityFadeIn.isRemovedOnCompletion = false
        opacityFadeIn.fillMode = .forwards

        let pulsing = CABasicAnimation(keyPath: "strokeColor")
        pulsing.toValue = UIColor(white: 1, alpha: 0.5).cgColor
        pulsing.repeatCount = 2
        pulsing.duration = 0.2
        pulsing.beginTime = CACurrentMediaTime() + 0.3 // wait for the fade in to occur

        let opacityFadeOut = CABasicAnimation(keyPath: "opacity")
        opacityFadeOut.fromValue = 1
        opacityFadeOut.toValue = 0
        opacityFadeOut.duration = 0.5
        opacityFadeOut.beginTime = CACurrentMediaTime() + 3 // seconds
        opacityFadeOut.isRemovedOnCompletion = false
        opacityFadeOut.fillMode = .forwards

        focusBoxLayer.add(opacityFadeIn, forKey: fadeInKey)
        focusBoxLayer.add(pulsing, forKey: pulseKey)
        focusBoxLayer.add(opacityFadeOut, forKey: fadeOutKey)
    }
    
    // MARK: - Private Properties
    
    func setupLayer(expCtr: Float = 0.0,
                    left: Bool = false) {
        lineX = left ? -13 : 63
        setupLayer(expCtr: expCtr)
    }
    func setupLayer(expCtr: Float) {

        sunCtr = 0.5 * lineLen * CGFloat(expCtr)
        self.changeShape()
    }
    private func changeShape() {
        focusBoxLayer.path = boxPath().cgPath
    }
    
    private func boxPath() -> UIBezierPath {
        // sunCtr = [0, 1]
        let path = UIBezierPath()
        
        // Draw the box
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 50, y: 0))
        path.addLine(to: CGPoint(x: 50, y: 50))
        path.addLine(to: CGPoint(x: 0, y: 50))
        path.addLine(to: CGPoint(x: 0, y: 0))
        
        // Draw the ticks
        path.move(to: CGPoint(x: 25, y: 0))
        path.addLine(to: CGPoint(x: 25, y: 4))
        path.move(to: CGPoint(x: 0, y: 25))
        path.addLine(to: CGPoint(x: 4, y: 25))
        path.move(to: CGPoint(x: 46, y: 25))
        path.addLine(to: CGPoint(x: 50, y: 25))
        path.move(to: CGPoint(x: 25, y: 46))
        path.addLine(to: CGPoint(x: 25, y: 50))

        // Create the line
        path.move(to: CGPoint(x: lineX, y: lineY + 0.5 * lineLen))
        path.addLine(to: CGPoint(x: lineX, y: lineY + sunCtr + 1.2 * size))
        path.move(to: CGPoint(x:lineX, y: lineY + sunCtr - 1.2 * size))
        path.addLine(to: CGPoint(x: lineX, y: lineY + -0.5 * lineLen))

        // Create the sun
        path.move(to: CGPoint(x: lineX + 0.383 * size, y: lineY + sunCtr - 0.924 * size))
        path.addLine(to: CGPoint(x: lineX + -0.383 * size, y: lineY + sunCtr + 0.924 * size))
        path.move(to: CGPoint(x: lineX + -0.924 * size, y: lineY + sunCtr - 0.383 * size))
        path.addLine(to: CGPoint(x: lineX + 0.924 * size, y: lineY + sunCtr + 0.383 * size))
        path.move(to: CGPoint(x: lineX + 0.924 * size, y: lineY + sunCtr - 0.383 * size))
        path.addLine(to: CGPoint(x: lineX + -0.924 * size, y: lineY + sunCtr + 0.383 * size))
        path.move(to: CGPoint(x: lineX + -0.383 * size, y: lineY + sunCtr - 0.924 * size))
        path.addLine(to: CGPoint(x: lineX + 0.383 * size, y: lineY + sunCtr + 0.924 * size))
        path.lineWidth = 1
        //path.stroke()

        return path
    }
    
    // MARK: - Unsupported Initializers
    
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
}
extension FocusBoxView: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if flag {
            self.changeShape()
        }
    }
}
