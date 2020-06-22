//
//  AppDelegate.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 1/9/20.
//  Copyright © 2020 Melissa A. Hines. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var extImageView: UIImageView!  // Reference to the external view (e.g., being AirPlayed)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // Keep track of number of launches
        let currentCount = UserDefaults.standard.integer(forKey: UserDefaultKeys.launchCount)
        UserDefaults.standard.set(currentCount + 1, forKey:UserDefaultKeys.launchCount)
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        switch connectingSceneSession.role.rawValue {
            case "UIWindowSceneSessionRoleApplication":
                return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
            case "UIWindowSceneSessionRoleExternalDisplay":
                return UISceneConfiguration(name: "External Configuration", sessionRole: connectingSceneSession.role)
            default:
                fatalError("Unknown Configuration \(connectingSceneSession.role.rawValue)")
            }
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

