//
//  AppInfoView.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 2/6/20.
//  Copyright © 2020 Melissa A. Hines. All rights reserved.
//

import UIKit

class AppInfoView: UIView {
    
    var isShowing: Bool = true

}
extension UIView {
    func fadeIn() {
        UIView.animate(withDuration: 0.5, delay: 0.0, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.alpha = 1.0
        }, completion: nil)
    }
    
    func fadeOut() {
        UIView.animate(withDuration: 0.5, delay: 0.0, options: UIView.AnimationOptions.curveEaseOut, animations: {
            self.alpha = 0.0
        }, completion: nil)
    }
}
