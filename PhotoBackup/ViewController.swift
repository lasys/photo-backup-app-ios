//
//  ViewController.swift
//  PhotoBackup
//
//  Created by Lachermeier on 08.05.19.
//  Copyright © 2019 Lachermeier. All rights reserved.
//

import UIKit
import Photos
import Alamofire


class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate{
    
    @IBOutlet weak var uploadButton: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var infoLabel: UILabel!
    
    var counter = 0
    var total = 0
    var errorOccured = false

    
    let semaphore = DispatchSemaphore(value: 1)
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        displayNumberOfAvailablePhotos()
    }
    
    
    func displayNumberOfAvailablePhotos() {
        DispatchQueue.global().async {
            PHPhotoLibrary.requestAuthorization { status in
                switch status {
                case .authorized:
                    let fetchOptions = PHFetchOptions()
                    let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                    DispatchQueue.main.sync {
                        self.infoLabel.text = "\(allPhotos.count) Bilder gefunden"
                    }
                    allPhotos.firstObject?.requestContentEditingInput(with: PHContentEditingInputRequestOptions(), completionHandler: {
                        (eidtingInput, info) in
                        if let input = eidtingInput, let imgURL = input.fullSizeImageURL {
                            let imageData = try! Data(contentsOf: imgURL)
                           DispatchQueue.main.async {
                                self.imageView.image = UIImage(data: imageData)
                           }
                        }
                    })
                    
                case .denied: print("denied")
                case .notDetermined: print("notDetermined")
                case .restricted: print("restricted")
                }
            }
        }
    }
    
    /*
 
     TODO:  - Exists Request -> danach erst upload
            - semaphore checken -> sequentiell
     - "Service Discovery": eigene IP herausfinden und dann jeden lokalen Rechner anpingen bzw anfragen auf bestimmte URL -> Server finden
 
 */
    
    func upload(imgURL: URL, timestamp: Int64) {
        
        let imageData = try! Data(contentsOf: imgURL)
        DispatchQueue.main.async {
            self.imageView.image = UIImage(data: imageData)
        }
        
        Alamofire.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(String(timestamp).data(using: .utf8)!, withName: "timestamp")
            multipartFormData.append(imageData,
                                     withName: "imagefile",
                                     fileName: "\(imgURL.absoluteString.split(separator: "/").last!)",
                                     mimeType: "image/\(imgURL.absoluteString.split(separator: ".").last!)")
        },
         to: "http://localhost:8080/image",
         encodingCompletion: { encodingResult in
            defer {
                print("defer")
                self.semaphore.signal()
            }
            switch encodingResult {
            case .success(let upload, _, _):
                upload.uploadProgress { progress in
                    print("process: \(Float(progress.fractionCompleted))%")
                }
                upload.validate()
                guard upload.response?.statusCode == 201 else {
                    if upload.response?.statusCode == nil {
                        self.errorOccured = true
                    }
                    print("Error: HttpStatusCode is \(upload.response?.statusCode)"); return
                }
//                upload.responseJSON { response in
//
//                    guard response.result.isSuccess,
//                        let value = response.result.value else {
//                            print("Error while uploading file: \(String(describing: response.result.error))")
//                            return
//                    }
//                    print(value)
//                }
                
                DispatchQueue.main.async {
                    self.counter += 1
                    self.infoLabel.text = "\(self.counter) von \(self.total) hochgeladen"
                }
                
            case .failure(let encodingError):
                print(encodingError)
            }
        })
    }
    
    
    
    @IBAction func button(_ sender: Any) {
        
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized:
                let fetchOptions = PHFetchOptions()
                let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                self.total = allPhotos.count
                self.counter = 0
                self.errorOccured = false
                DispatchQueue.main.async {
                    self.uploadButton.isEnabled = false
                }
                self.semaphore.signal()
                
                for index in 0...allPhotos.count - 1 {
                    
                    self.semaphore.wait()
                    
                    if (self.errorOccured) {
                        DispatchQueue.main.async {
                            self.infoLabel.text = "Upload abgebrochen - keine Verbindung zum Server!"
                            self.uploadButton.isEnabled = true
                        }
                        return
                    }
                    
                    sleep(2)
                    let image:PHAsset = allPhotos.object(at: index)
                    
                    image.requestContentEditingInput(with: PHContentEditingInputRequestOptions(), completionHandler: { (eidtingInput, info) in
                        if let input = eidtingInput, let imgURL = input.fullSizeImageURL {
                            let timestamp = Int64((image.creationDate!.timeIntervalSince1970) * 1000)
                            self.upload(imgURL: imgURL, timestamp: timestamp)
                        }
                    })
                }
            case .denied, .restricted:
                print("Not allowed")
            case .notDetermined:
                // Should not see this when requesting
                print("Not determined yet")
            }
        }
    }
    
    
}
