//
//  ExtViewController.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 1/19/20.
//  Copyright © 2020 Melissa A. Hines. All rights reserved.
//

import UIKit
import AVFoundation


class ExtViewController: UIViewController {

    
    @IBOutlet var extPreviewView: UIView!
    @IBOutlet var extImageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.extImageView = extImageView
        NotificationCenter.default.post(name: .ExtViewActivated, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.extImageView = nil
        NotificationCenter.default.post(name: .ExtViewDeactivated, object: nil)
    }
}
