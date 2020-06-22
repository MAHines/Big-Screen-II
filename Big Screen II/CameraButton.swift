//
//  CameraButton.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 2/2/20.
//  Copyright © 2020 Melissa A. Hines. All rights reserved.
//

import UIKit

class CameraButton: UIButton {

    override func awakeFromNib()
    {
        setImage(UIImage(systemName: "circle.fill"), for: .normal)
        setImage(UIImage(systemName: "circle.fill"), for: .disabled)
        setImage(UIImage(systemName: "stop.fill"), for: .selected)
        setColor()
    }
    
    override open var isSelected: Bool {
        didSet {
            setColor()
        }
    }
    override open var isEnabled: Bool {
        didSet {
            setColor()
        }
    }
    func setColor(){
        if !isEnabled {
            tintColor = .darkGray
        } else if isSelected {
            tintColor = .red
        } else {
            tintColor = .green
        }
    }

}
