//
//  CameraViewSessionTypes.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 2/6/20.
//  Copyright © 2020 Melissa A. Hines. All rights reserved.
//

import Foundation

public enum CameraViewSessionError: Error {

    case failedToAddAudioInput
    case failedToAddVideoInput
    case failedToFindVideoDevice
    case unableToCaptureVideo
    case unableToSaveVideo
    case unableToRecordVideo
    case changePrivacySettings
    
    
    public var localizedDescription: String {
        switch self {
        case .failedToAddAudioInput:
            return "No audio input available."
        case .failedToAddVideoInput:
            return "No video input available."
        case .failedToFindVideoDevice:
            return "No video device available"
        case .changePrivacySettings:
            return "Big Screen II doesn't have permission to use the camera, please change privacy settings"
        case .unableToCaptureVideo:
            return "Unable to capture video"
        case .unableToSaveVideo:
            return "Unable to save video"
        case .unableToRecordVideo:
            return "Unable to record video"
        }
    }
}

public struct UserDefaultKeys {
    static let launchCount = "launchCount"
    static let lastVersionPromptedForReview = "lastVersionPromptedForReview"
    static let lastCamera = "lastCamera"
    static let lastPosition = "lastPosition"
}

extension Notification.Name {
    static let ExtViewActivated = Notification.Name("extViewActivated")
    static let ExtViewDeactivated = Notification.Name("extViewDeactivated")
}

extension String {
    
    var length: Int {
        return count
    }
    
    subscript (i: Int) -> String {
        return self[i ..< i + 1]
    }
    
    func substring(fromIndex: Int) -> String {
        return self[min(fromIndex, length) ..< length]
    }
    
    func substring(toIndex: Int) -> String {
        return self[0 ..< max(0, toIndex)]
    }
    
    subscript (r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
                                            upper: min(length, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return String(self[start ..< end])
    }
}
