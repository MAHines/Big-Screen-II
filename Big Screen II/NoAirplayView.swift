//
//  NoAirplayView.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 2/3/20.
//  Copyright © 2020 Melissa A. Hines. All rights reserved.
//

import UIKit

class NoAirplayView: UIView {
    
    public override func draw(_ frame: CGRect) {
        let h = frame.height
        let w = frame.width
        let color:UIColor = UIColor.darkGray

        let bpath: UIBezierPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 20)

        color.set()
        bpath.stroke()
        bpath.fill(with: .normal, alpha: 0.7)
    }
}
