//
//  CameraViewController.swift
//  Big Screen II
//
//  Created by Melissa A. Hines on 1/11/20.
//  Copyright © 2020 Melissa A. Hines. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import WebKit
import StoreKit

class CameraViewController: UIViewController, UIGestureRecognizerDelegate {

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    private var isRecording: Bool = false {
        didSet {
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.switchCameraButton.isEnabled = !self.isRecording && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.recordButton.isSelected = self.isRecording
                self.displayAppInfoButton.isEnabled = !self.isRecording
                if self.isRecording {
                    self.seconds = 0
                    self.runTimer()
                    self.videoTimeLabel.isHidden = false
                } else {
                    self.timer.invalidate()
                }
            }
        }
    }

    private var setupResult: SessionSetupResult = .success
    private var keyValueObservations = [NSKeyValueObservation]()

    private let sessionQueue = DispatchQueue(label: "session queue")
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    private var extOrientation: UIImage.Orientation = .up
    private var cameraOrientation: AVCaptureVideoOrientation = .portrait
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var focusBoxView: FocusBoxView?
    private var outputFileLocation: URL?
    private var sessionAtSourceTime: CMTime?
    private var isAirplayConnected = false
    private var timer = Timer()
    private var seconds = 0
    private var stopWaitForPanTime: DispatchTime = DispatchTime.now()
    private var startPanPosition: CGFloat = 0
    private var panning: Bool = false
    private var relativeBias: Float = 0.0
     
    @IBOutlet var focusTap: UITapGestureRecognizer!
    @IBOutlet var autofocusDoubleTap: UITapGestureRecognizer!
    @IBOutlet var toggleAirplayTripleTap: UITapGestureRecognizer!
    @IBOutlet var exposePan: UIPanGestureRecognizer!
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    @IBOutlet var infoWebView: WKWebView!
    @IBOutlet var airplayAlert: NoAirplayView!
    @IBOutlet var previewView: PreviewView!
    @IBOutlet var appInfoView: AppInfoView!
    @IBOutlet var switchCameraButton: UIButton!
    @IBOutlet var displayAppInfoButton: UIButton!
    @IBOutlet var zoomSlider: UISlider!
    @IBOutlet private var recordButton: CameraButton!
    @IBOutlet var videoTimeLabel: UILabel!
    @IBAction private func doFocusAndExpose(_ gestureRecognizer: UITapGestureRecognizer) {
        let touchPoint = gestureRecognizer.location(in: self.view)
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        
        // Only focus if touch is within previewView
        let rect = CGRect(x:0, y:0, width:1, height:1)
        if rect.contains(devicePoint) {
            var left = cameraOrientation == .portrait ? devicePoint.y > 0.5 : devicePoint.x > 0.5
            if !(self.videoDeviceInput?.device.position == .front) && cameraOrientation == .portrait {
                left.toggle()
            }
            focusBoxView?.setupLayer(expCtr: 0.0,
                                     left: left)
            stopWaitForPanTime = DispatchTime.now() + 3.0
            focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint)
            focusBoxView?.showBox(at: touchPoint)
        }
    }
    @IBAction private func doAutofocus(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = CGPoint(x:0.5,y:0.5)
        focusBoxView?.vanishBox()
        stopWaitForPanTime = DispatchTime.now() - 1.0
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint)
    }
    @IBAction private func doToggleAirplayWarning(_ gestureRecognizer: UITapGestureRecognizer) {
        DispatchQueue.main.async {
            if !self.isAirplayConnected{
                self.airplayAlert.isHidden = !self.airplayAlert.isHidden
            }
        }
    }
    @IBAction private func doAdjustExposure(_ panGesture: UIPanGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: panGesture.location(in: panGesture.view))
        if panning || DispatchTime.now() < stopWaitForPanTime {
             if panGesture.state == .began {
                startPanPosition = cameraOrientation == .portrait ? devicePoint.x : devicePoint.y
                panning = true
                focusBoxView?.showBox()
            } else if panGesture.state == .changed || panGesture.state == .ended {
                let panPosition = cameraOrientation == .portrait ? devicePoint.x : devicePoint.y
                let distance = -2 * (panPosition - startPanPosition)
                setExposure(relBias: Float(distance.clamped(to: -1.0...1.0)))
                focusBoxView?.setupLayer(expCtr: -relativeBias)
            }
            if panGesture.state == .ended {
                panning = false
                stopWaitForPanTime = DispatchTime.now() + 3.0
                focusBoxView?.hideBox()
            }
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }

    // MARK: View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addAirplayObservers()
        
        switchCameraButton.isEnabled = false
        recordButton.isEnabled = false
        zoomSlider.isEnabled = false
        videoTimeLabel.isHidden = true
        
        focusTap.delegate = self
        autofocusDoubleTap.delegate = self
        toggleAirplayTripleTap.delegate = self
        exposePan.delegate = self
        focusTap.numberOfTapsRequired = 1
        autofocusDoubleTap.numberOfTapsRequired = 2
        toggleAirplayTripleTap.numberOfTapsRequired = 3
        focusTap.require(toFail: autofocusDoubleTap)
        focusTap.require(toFail: toggleAirplayTripleTap)
        autofocusDoubleTap.require(toFail: toggleAirplayTripleTap)
        
        // Load information into the appInfoView
        let urlPath = Bundle.main.url(forResource: "index", withExtension: "html")
        let content = URLRequest(url: urlPath!)
        infoWebView.load(content)
        self.appInfoView.alpha = 0.0
        self.appInfoView.isShowing = false
        infoWebView.navigationDelegate = self   // Needed to handle support e-mail
        
        // Set up the video preview view.
        previewView.session = session
        
        // Set up the focus box
        focusBoxView = FocusBoxView()
        view.addSubview(focusBoxView!)
                
        // Make sure Airplay status is correct. This shouldn't be necessary, but does no harm
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        DispatchQueue.main.async{
            self.isAirplayConnected = appDelegate.extImageView != nil
            self.airplayAlert.isHidden = appDelegate.extImageView != nil
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }
        
        sessionQueue.async {
            self.configureSession()
        }
        
        // Ask for a review if the product has been used at least 4 times and Airplay is inactive
        let launchCount = UserDefaults.standard.integer(forKey: UserDefaultKeys.launchCount)
        
        // Get the current bundle version for the app
        let infoDictionaryKey = kCFBundleVersionKey as String
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
            else { fatalError("Expected to find a bundle version in the info dictionary") }
        
        let lastVersionPromptedForReview = UserDefaults.standard.string(forKey: UserDefaultKeys.lastVersionPromptedForReview)
        
        if launchCount >= 4 && currentVersion != lastVersionPromptedForReview {
            let twoSecondsFromNow = DispatchTime.now() + 2.0
            DispatchQueue.main.asyncAfter(deadline: twoSecondsFromNow) {
                if !self.isAirplayConnected{
                    SKStoreReviewController.requestReview()
                    UserDefaults.standard.set(currentVersion, forKey: UserDefaultKeys.lastVersionPromptedForReview)
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only start the session if setup succeeded.
                self.addSessionObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                self.presentChangePrivacySettingsAlert()
            case .configurationFailed:
                self.presentNoVideoAlert()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        super.viewWillDisappear(animated)
    }
    
    override func viewWillLayoutSubviews() {
        
        let orientation: UIDeviceOrientation = UIDevice.current.orientation
        let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection
        let front = self.videoDeviceInput?.device.position == .front
        
        switch (orientation) {
        case .portrait:
            videoPreviewLayerConnection?.videoOrientation = .portrait
            cameraOrientation = .portrait
            if front {extOrientation = .leftMirrored} else {extOrientation = .right}
        case .landscapeRight:
            videoPreviewLayerConnection?.videoOrientation = .landscapeLeft
            cameraOrientation = .landscapeLeft
            if front {extOrientation = .upMirrored} else {extOrientation = .down}
        case .landscapeLeft:
            videoPreviewLayerConnection?.videoOrientation = .landscapeRight
            cameraOrientation = .landscapeRight
            if front {extOrientation = .downMirrored} else {extOrientation = .up}
        case .portraitUpsideDown:
            videoPreviewLayerConnection?.videoOrientation = .portraitUpsideDown // was .portrait?
            cameraOrientation = .portraitUpsideDown
            if front {extOrientation = .rightMirrored} else {extOrientation = .left}
        default:     // Don't make any changes if orientation cannot be determined (unknown) or horizontal
            break
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
            cameraOrientation = newVideoOrientation
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if (touch.view is UIButton) {
            return false
        } else if (touch.view is UISlider){
            return false
        }
        return true
    }

    // MARK: Zooming
    @IBAction func zoomSliderChanged(_ sender: UISlider) {
        let device = self.videoDeviceInput.device
        let maxZoom = device.maxAvailableVideoZoomFactor/4      // maxAvailableVideoZoomFactor insanely high
        let newZoom = exp(log(maxZoom) * CGFloat(sender.value)) // Use log ramp
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Zoom factors range from 1 to the maxAvailableVideoZoomFactor/4
                device.ramp(toVideoZoomFactor: newZoom, withRate: 100.0)
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: Focusing & Setting Exposure
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint) {
        
        relativeBias = 0.0
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.setExposureTargetBias(0, completionHandler: nil)
                }
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    private func setExposure(relBias: Float) {
        let device = self.videoDeviceInput.device
        let newExposureBias = (relBias > 0) ? relBias * device.maxExposureTargetBias : -relBias * device.minExposureTargetBias
        relativeBias = relBias
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                if device.isExposureModeSupported(.autoExpose) {
                    device.setExposureTargetBias(newExposureBias, completionHandler: nil)
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: Session Management
    private func configureSession() {
        if setupResult != .success {
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        do {
            try addVideoInput()
            addVideoOutput()
            do {
                try addAudioInput()
                addAudioOutput()
            }
            catch {
                print("Audio unavailable")
            }
            self.session.commitConfiguration()
        } catch {
            print("Video unavailable.")
        }
    }
    
    private func addVideoInput() throws {
        let lastCamera = UserDefaults.standard.string(forKey: UserDefaultKeys.lastCamera) ?? "builtInTrueDepthCamera"
        let lastPosition = UserDefaults.standard.integer(forKey: UserDefaultKeys.lastPosition)
        let preferredDeviceType: AVCaptureDevice.DeviceType = AVCaptureDevice.DeviceType(rawValue: lastCamera)
        var preferredPosition: AVCaptureDevice.Position = AVCaptureDevice.Position(rawValue: lastPosition)!
        if preferredPosition == .unspecified {
            preferredPosition = .back
        }
        
        let devices = self.videoDeviceDiscoverySession.devices
        var newVideoDevice: AVCaptureDevice? = nil
        
        // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
        if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
            newVideoDevice = device
        } else if let device = devices.first(where: { $0.position == preferredPosition }) {
            newVideoDevice = device
        }
        extOrientation = (newVideoDevice?.position == .front) ? .downMirrored : .up
        
        guard let videoDevice = newVideoDevice else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            throw CameraViewSessionError.failedToFindVideoDevice
        }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            throw CameraViewSessionError.failedToAddVideoInput
        }

        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            DispatchQueue.main.async {
                var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                if self.windowOrientation != .unknown {
                    if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                        initialVideoOrientation = videoOrientation
                    }
                }
                self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
            }
            writeCameraDefaults()
        } else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            throw CameraViewSessionError.failedToAddVideoInput
        }
    }

    private func addAudioInput() throws {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw CameraViewSessionError.failedToAddAudioInput
        }
        guard let audioDeviceInput = try? AVCaptureDeviceInput(device: (audioDevice)) else {
            throw CameraViewSessionError.failedToAddAudioInput
        }

        if session.canAddInput(audioDeviceInput) {
            session.addInput(audioDeviceInput)
        } else {
            throw CameraViewSessionError.failedToAddAudioInput
        }
    }
    private func addVideoOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        let videoCaptureQueue = DispatchQueue(label: "videoBufferQueue", attributes: .concurrent)
        videoOutput.videoSettings = nil
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoCaptureQueue)
        if self.session.canAddOutput(videoOutput) {
            self.session.addOutput(videoOutput)
        }
        self.videoOutput = videoOutput
    }
    private func addAudioOutput() {
        let audioOutput = AVCaptureAudioDataOutput()
        let audioCaptureQueue = DispatchQueue(label: "audioBufferQueue", attributes: .concurrent)
        audioOutput.setSampleBufferDelegate(self, queue: audioCaptureQueue)
        if self.session.canAddOutput(audioOutput) {
            self.session.addOutput(audioOutput)
        }
        self.audioOutput = audioOutput
    }
  
    func startWritingAV() throws {
        outputFileLocation = videoFileLocation()
        videoWriter = try? AVAssetWriter(outputURL: outputFileLocation!, fileType: AVFileType.mov)
        guard videoWriter != nil else {
            throw CameraViewSessionError.unableToCaptureVideo
        }
        
        // Does device support 1280 x 720? Hardware encoding?
        let exportPresets = AVAssetExportSession.allExportPresets()
        if !exportPresets.contains(AVAssetExportPreset1280x720) {
            throw CameraViewSessionError.unableToRecordVideo
        }
        let codec = exportPresets.contains(AVAssetExportPresetHEVCHighestQuality) ? AVVideoCodecType.hevc : AVVideoCodecType.h264

        // Add video input. iPhone 11 Pro does not like 1280 width/720 height
        videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video,
                                              outputSettings: [AVVideoCodecKey : codec,
                                                               AVVideoWidthKey : 1280,
                                                               AVVideoHeightKey : 719, // 720 causes problems on iPhone 11 Pro
                                                               AVVideoCompressionPropertiesKey : [AVVideoAverageBitRateKey : 2300000],
        ])

        videoWriterInput?.expectsMediaDataInRealTime = true

        // Set correct orientation for the saved video
        videoWriterInput?.transform = getVideoTransform()

        if videoWriter!.canAdd(videoWriterInput!) {
            videoWriter!.add(videoWriterInput!)
        } else {
            throw CameraViewSessionError.unableToCaptureVideo
        }

        // add audio input
        audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: nil)
        audioWriterInput!.expectsMediaDataInRealTime = true

        if videoWriter!.canAdd(audioWriterInput!) {
            videoWriter!.add(audioWriterInput!)
        }

        videoWriter!.startWriting()
    }
    
    private func getVideoTransform() -> CGAffineTransform {
        
        let currentVideoDevice = self.videoDeviceInput.device
        let front = currentVideoDevice.position == .front
        var t = CGAffineTransform.identity
        
        if front {
            t = t.scaledBy(x:-1.0, y:1.0)
        }
        
        switch cameraOrientation { // UIDevice.current.orientation sometimes returns unknown
            case .portrait:
                t = t.rotated(by: .pi/2.0)
                return t
            case .portraitUpsideDown:
                t = t.rotated(by: -.pi/2.0)
                return t
            case .landscapeLeft:
                if !front {t = t.rotated(by: .pi)}
                return t
            case .landscapeRight:
                if front {t = t.rotated(by: .pi)}
                return t
            default:
                print("****** default") // Not good
                return .identity
        }
    }
    
    func canWrite() -> Bool {
        return isRecording && videoWriter != nil && videoWriter?.status == .writing
    }

    //video file location method
    func videoFileLocation() -> URL {
        // Start recording video to a temporary file.
        let outputFileName = "BigScreenII" + NSUUID().uuidString
        var videoOutputURL: URL = URL(fileURLWithPath: NSTemporaryDirectory())
        videoOutputURL.appendPathComponent(outputFileName)
        videoOutputURL.appendPathExtension("mov")
        return videoOutputURL
    }
    
    // MARK: Device Configuration
    
    // Put the device types in your order of preference
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera, .builtInTrueDepthCamera],
                                                                               mediaType: .video, position: .unspecified)
    
    private func writeCameraDefaults() {
        let videoDevice = self.videoDeviceInput.device
        let rawCameraString: String = videoDevice.deviceType.rawValue
        let cameraString = String(rawCameraString[19].lowercased()) + String(rawCameraString.substring(fromIndex: 20))
        let position: Int = videoDevice.position.rawValue
        UserDefaults.standard.set(cameraString, forKey: UserDefaultKeys.lastCamera)
        UserDefaults.standard.set(position, forKey: UserDefaultKeys.lastPosition)
    }
    
     @IBAction private func switchCamera(_ switchCameraButton: UIButton) {

        DispatchQueue.main.async {
            self.switchCameraButton.isEnabled = false
            self.recordButton.isEnabled = false
            self.zoomSlider.setValue(0.0, animated: false)
        }

        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            
            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInTripleCamera
                self.extOrientation = .up
            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInTrueDepthCamera
                self.extOrientation = .downMirrored
            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
            }
            let devices = self.videoDeviceDiscoverySession.devices
            print(devices.description)
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    
                    self.session.commitConfiguration()
                    self.writeCameraDefaults()
                    
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.switchCameraButton.isEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.recordButton.isEnabled = true
            }
         }
    }
    
    // MARK: Recording Movie
        
    @IBAction private func toggleMovieRecording(_ recordButton: UIButton) {
        
        sessionQueue.async {
            if !self.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                self.sessionAtSourceTime = nil
                do {
                    try self.startWritingAV()
                    self.isRecording = true
                } catch {
                    self.presentUnableToRecordVideoAlert()
                    return
                }
            } else {
                self.isRecording = false
                self.videoWriterInput!.markAsFinished()
                self.videoWriter!.finishWriting { [weak self] in
                    self?.sessionAtSourceTime = nil
                    self?.moveToPhotoLibrary()
                }
            }
         }
    }
    
    private func moveToPhotoLibrary() {
        // Check the authorization status.
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // Save the movie file to the photo library and cleanup.
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: self.outputFileLocation!, options: options)
                }, completionHandler: { success, error in
                    if !success {
                        print("Big Screen II couldn't save the movie to your photo library: \(String(describing: error))")
                    }
                    self.cleanup()
                }
                )
            } else {
                self.cleanup()
            }
        }
    }

    private func cleanup() {
        let path = outputFileLocation!.path
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                print("Could not remove file at url: \(String(describing: outputFileLocation))")
            }
        }
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
            
            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
    }
    
    // MARK: Recording Timer

    func runTimer() {
         timer = Timer.scheduledTimer(timeInterval: 1, target: self,   selector: (#selector(updateTimer)), userInfo: nil, repeats: true)
    }
    @objc func updateTimer() {
        seconds += 1
        videoTimeLabel.text = timeString(time: TimeInterval(seconds))
    }
    func timeString(time:TimeInterval) -> String {
        let hours = Int(time)/3600
        let minutes = Int(time)/60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

 
    // MARK: Display Airplay Warning
        
    @objc private func hideAirplayWarning(_ notification:Notification) {
        isAirplayConnected = true
        DispatchQueue.main.async {
            self.airplayAlert.isHidden = true
        }
    }
    @objc private func showAirplayWarning(_ notification:Notification) {
        isAirplayConnected = false
        DispatchQueue.main.async {
            self.airplayAlert.isHidden = false
        }
    }
    
    // MARK: Display Application Info
        
    @IBAction private func displayAppInfo(_ displayAppInfoButton: UIButton) {
        DispatchQueue.main.async {
            if self.appInfoView.isShowing {
                self.appInfoView.fadeOut()
                self.appInfoView.isShowing = false
                self.switchCameraButton.isEnabled = self.isSessionRunning
                self.recordButton.isEnabled = self.isSessionRunning
                self.zoomSlider.isEnabled = self.isSessionRunning
            } else {
                self.appInfoView.fadeIn()
                self.appInfoView.isShowing = true
                self.switchCameraButton.isEnabled = false
                self.recordButton.isEnabled = false
                self.zoomSlider.isEnabled = false
            }
        }
    }
    
    // MARK: KVO and Notifications
    
    /// - Tag: ObserveInterruption
    private func addSessionObservers() {
        let keyValueObservationIsRunning = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.switchCameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1 && !self.appInfoView.isShowing
                self.recordButton.isEnabled = isSessionRunning && !self.appInfoView.isShowing
                self.zoomSlider.isEnabled = isSessionRunning && !self.appInfoView.isShowing
            }
        }
        keyValueObservations.append(keyValueObservationIsRunning)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    private func addAirplayObservers() {

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(hideAirplayWarning(_:)),
                                               name: .ExtViewActivated,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showAirplayWarning(_:)),
                                               name: .ExtViewDeactivated,
                                               object: nil)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    /// - Tag: HandleRuntimeError
    @objc func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }
    
    /// - Tag: HandleInterruption
    @objc func sessionWasInterrupted(notification: NSNotification) {
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
        }
    }
    
    @objc func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
    }
    
    // MARK: Present Alerts

    func presentNoVideoAlert() {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Big Screen II", message: CameraViewSessionError.unableToCaptureVideo.localizedDescription, preferredStyle: .alert)
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK",
                                                                             comment: "Alert OK button"),
                                                    style: .cancel,
                                                    handler: nil))
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func presentChangePrivacySettingsAlert() {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Big Screen II", message: CameraViewSessionError.changePrivacySettings.localizedDescription, preferredStyle: .alert)
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                    style: .cancel,
                                                    handler: nil))
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings",
                                                                             comment: "Alert button to open Settings"),
                                                    style: .`default`,
                                                    handler: { _ in
                                                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                  options: [:],
                                                                                  completionHandler: nil)
            }))
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
    func presentUnableToRecordVideoAlert() {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Big Screen II", message: CameraViewSessionError.unableToRecordVideo.localizedDescription, preferredStyle: .alert)
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK",
                                                                             comment: "Alert OK button"),
                                                    style: .cancel,
                                                    handler: nil))
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        return uniqueDevicePositions.count
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let writable = canWrite()

        if writable,
            sessionAtSourceTime == nil {
            sessionAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            videoWriter!.startSession(atSourceTime: sessionAtSourceTime!)
        }

        if writable,
            output == videoOutput,
            (videoWriterInput!.isReadyForMoreMediaData) {
            videoWriterInput!.append(sampleBuffer)
        } else if writable,
            output == audioOutput,
            (audioWriterInput!.isReadyForMoreMediaData) {
            audioWriterInput?.append(sampleBuffer)
        }

        // Write to the external monitor
        if output == videoOutput {
            let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            let ciimage : CIImage = CIImage(cvPixelBuffer: imageBuffer)
            let image : UIImage = self.convert(cmage: ciimage)
            
            DispatchQueue.main.sync(execute: {() -> Void in
                let appDelegate = UIApplication.shared.delegate as! AppDelegate
                if let imageView = appDelegate.extImageView {imageView.image = image}
            })
        }
    }
    
    // Convert CIImage to CGImage
    private func convert(cmage:CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage, scale: 1.0, orientation: extOrientation)
        return image
    }    
}

// MARK: - Sending e-mail from infoWebView
extension CameraViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard
            let url = navigationAction.request.url,
            let scheme = url.scheme else {
                decisionHandler(.cancel)
                return
        }

        if (scheme.lowercased() == "mailto") {
            // Set the subject and put version information in body
            let dictionary = Bundle.main.infoDictionary!
            let version = dictionary["CFBundleShortVersionString"] as! String
            let build = dictionary["CFBundleVersion"] as! String
            var body = "\n\n\n\n----\n"
            body += "Big Screen II Version: " + version + " (Build " + build + ")"
            body += "\n----\n"
            let queryItems = [URLQueryItem(name: "subject", value: "Big Screen II"),URLQueryItem(name: "body", value: body)]
            var newUrlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            newUrlComponents?.queryItems = queryItems

            UIApplication.shared.open((newUrlComponents?.url!)!, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.allow)
        }
    }
}
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
