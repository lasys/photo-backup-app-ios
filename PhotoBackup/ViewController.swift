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
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var infoLabel: UILabel!
    
    let pickerController = UIImagePickerController()
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        pickerController.delegate = self
        pickerController.allowsEditing = true
        pickerController.mediaTypes = ["public.image", "public.movie"]
        pickerController.sourceType = .photoLibrary
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        for k in info.keys {
            print(k)
        }
        let url = info[UIImagePickerController.InfoKey.imageURL]
        print(url)
        //        print(url)
        let data = try! Data(contentsOf: url as! URL)
        var source: CGImageSource = CGImageSourceCreateWithData((data as! CFMutableData), nil)!
        var metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [AnyHashable: Any]
        print(metadata![kCGImagePropertyExifDateTimeOriginal])
        print(metadata![kCGImagePropertyExifDateTimeDigitized])
        print(metadata)
        //                for key in metadata!.keys {
        //                    print(metadata![key])
        //                }
        
        
        
        
        
        
        
        dismiss(animated: true, completion:nil)
        
        
        
        
        
    }
    
    @IBAction func button(_ sender: Any) {
        
        
        //        present(pickerController, animated: true)
        
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized:
                let fetchOptions = PHFetchOptions()
                let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                //                for i in 0...allPhotos.count - 1 {
                //                    let i:PHAsset = allPhotos.object(at: i)
                //                    print(i.creationDate)
                //                    i.requestContentEditingInput(with: PHContentEditingInputRequestOptions(), completionHandler: { (eidtingInput, info) in
                //                        if let input = eidtingInput, let imgURL = input.fullSizeImageURL {
                //                            // imgURL
                //                            print(imgURL)
                //                            let d = try! Data(contentsOf: imgURL)
                //
                //                        }
                //
                //                    })
                //
                //                }
                
                let image = allPhotos.lastObject
                image?.requestContentEditingInput(with: PHContentEditingInputRequestOptions(), completionHandler: {
                    (eidtingInput, info) in
                    if let input = eidtingInput, let imgURL = input.fullSizeImageURL {
                        // imgURL
                        print(imgURL)
                        let imageData = try! Data(contentsOf: imgURL)
                        
                        let d = Int64((image?.creationDate!.timeIntervalSince1970)! * 1000)
                        
                        Alamofire.upload(multipartFormData: { multipartFormData in
                            multipartFormData.append(String(d).data(using: .utf8)!,
                                                     withName: "timestamp")
                            multipartFormData.append(imageData,
                                                     withName: "imagefile",
                                                     fileName: "\(imgURL.absoluteString.split(separator: "/").last!)",
                                mimeType: "image/\(imgURL.absoluteString.split(separator: ".").last!)")
                        },
                                         to: "http://localhost:8080/image",
                                         encodingCompletion: { encodingResult in
                                            switch encodingResult {
                                            case .success(let upload, _, _):
                                               print("success")
                                            case .failure(let encodingError):
                                                print(encodingError)
                                            }
                        })
                    }
                    
                })
                
               
                
                
                print("Found \(allPhotos.count) assets")
            case .denied, .restricted:
                print("Not allowed")
            case .notDetermined:
                // Should not see this when requesting
                print("Not determined yet")
            }
        }
        
        //        let image = imageView.image
        //
        //
        //        var imagedata = image.
        //        var source: CGImageSource = CGImageSourceCreateWithData((imagedata as! CFMutableData), nil)!
        //        var metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [AnyHashable: Any]
        //        print(metadata![kCGImagePropertyExifDateTimeOriginal])
        //        print(metadata![kCGImagePropertyExifDateTimeDigitized])
        //        print(metadata)
        //        for key in metadata!.keys {
        //            print(metadata![key])
        //        }
        
        
        
        
        
        
        
    }
    
    

}

