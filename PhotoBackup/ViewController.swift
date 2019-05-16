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
import Darwin

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate{
    
    //TODO: Refactoring Serversuche und getIPAdr
    //      - loading alert anzeigen bis Server gefunden wurde 
   
    
    @IBOutlet weak var uploadButton: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var infoLabel: UILabel!
    
    var counter = 0
    var total = 0
    var errorOccured = false
    
    var serverIP = ""

    
    let semaphore = DispatchSemaphore(value: 0)
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        displayNumberOfAvailablePhotos()
        
        print("IP: \(getLocalIPAddress())")
        DispatchQueue.global().async {
             self.findServer()
        }
        
        self.uploadButton.isEnabled = false
       
    }
    
    func findServer() {
        let partOfIPAddress = getLocalIPAddress().split(separator: ".").dropLast()
        
        let s = partOfIPAddress.joined(separator: ".")
        print(s)
        for präfix in 1...255 {
            let tmp = "\(s).\(präfix)"
            findServerRequest(ip: tmp, completion: { response in
                if (response) {
                    self.serverIP = tmp
                    DispatchQueue.main.async {
                        // Alert Server found!
                        self.uploadButton.isEnabled = true
                    }
                }
                print(response)
            })
        }
    }
    
    func findServerRequest(ip: String, completion: @escaping (Bool) -> Void){

        let url = "http://\(ip):8080/backup"
        Alamofire.request(url)
            .responseJSON(completionHandler: {response in
                switch response.response?.statusCode {
                case 204: print("\(ip): found server")
                completion(true)
                default: print("\(ip): no server")
                completion(false)
                }
            })
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
    
    
    func exists(name: String, timestamp: Int64, completion: @escaping (Bool?) -> Void) {
        Alamofire.request("http://localhost:8080/exists", parameters: ["name": name, "timestamp":timestamp])
            .responseJSON(completionHandler: {response in
                switch response.response?.statusCode {
                case 404:
                    print("not found")
                    completion(false)
                case 200: print("ok")
                    completion(true)
                case 400: print("bad request")
                    completion(nil)
                default: print("other status code: \(String(describing: response.response?.statusCode))")
                    completion(nil)
                }
          })
    }
    
    func upload(imgURL: URL, timestamp: Int64, completion: @escaping (Bool) -> Void) {
        
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

            switch encodingResult {
            case .success(let upload, _, _):
//                upload.uploadProgress { progress in
//                    print("process: \(Float(progress.fractionCompleted))%")
//                }
               // upload.validate()
//                guard upload.response?.statusCode == 201 else {
//                    if upload.response?.statusCode == nil {
//                        self.errorOccured = true
//                    }
//                    print("Error: HttpStatusCode is \(upload.response?.statusCode)"); return
//                }
                
                upload.responseJSON { response in
                    
//                    guard response.result.isSuccess else {
//                            print("Error while uploading file: \(String(describing: response.result.error))")
//                            return
//                    }
                    print("StatusCode: \(response.response?.statusCode)")
                    //print(value)
                    guard let statusCode = response.response?.statusCode else  {
                        print("Something went wrong while uploading: response is nul!"); completion(false); return
                    }
                    if statusCode == 201 {
                        completion(true)
                        
                    } else {
                        print("Something went wrong while uploading: response is nul!")
                        completion(false)
                    }
                    
                    
                    
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
                    print("\(index) waiting..")
                    self.semaphore.wait()
                    print("\(index) entered..")
                    if (self.errorOccured) {
                        DispatchQueue.main.async {
                            self.infoLabel.text = "Upload abgebrochen - keine Verbindung zum Server!"
                            self.uploadButton.isEnabled = true
                        }
                        return
                    }
                    
                   // sleep(2)
                    let image:PHAsset = allPhotos.object(at: index)
                    
                    image.requestContentEditingInput(with: PHContentEditingInputRequestOptions(), completionHandler: { (eidtingInput, info) in
                        if let input = eidtingInput, let imgURL = input.fullSizeImageURL {
                            let timestamp = Int64((image.creationDate!.timeIntervalSince1970) * 1000)
//                            self.upload(imgURL: imgURL, timestamp: timestamp)
                            self.exists(name: "\(imgURL.absoluteString.split(separator: "/").last!)", timestamp: timestamp,  completion: { result in
                                guard let exists = result else {
                                    self.semaphore.signal()
                                    return
                                }
                                if (exists == false) {
                                    print("Image not existing - upload")
                                    self.upload(imgURL: imgURL, timestamp: timestamp, completion: { result in
                                        if result {
                                            DispatchQueue.main.async {
                                                self.counter += 1
                                                self.infoLabel.text = "\(self.counter) von \(self.total) hochgeladen"
                                            }
                                        } else {
                                            DispatchQueue.main.async {
                                                self.infoLabel.text = "\(self.counter) von \(self.total) Fehler beim Hochladen!"
                                            }
                                        }
                                        self.semaphore.signal()
                                    })
                                } else {
                                    self.semaphore.signal()
                                }
                            })
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
    
    func getLocalIPAddress() -> String {
        
        var temp = [CChar](repeating: 0, count: 255)
        enum SocketType: Int32 {
            case  SOCK_STREAM = 0, SOCK_DGRAM, SOCK_RAW
        }
        
        // host name
        gethostname(&temp, temp.count)
        // create addrinfo based on hints
        // if host name is nil or "" we can connect on localhost
        // if host name is specified ( like "computer.domain" ... "My-MacBook.local" )
        // than localhost is not aviable.
        // if port is 0, bind will assign some free port for us
        
        var port: UInt16 = 0
        let hosts = ["localhost", String(cString: temp)]
        var hints = addrinfo()
        hints.ai_flags = 0
        hints.ai_family = PF_UNSPEC
        
        for host in hosts {
            guard host.contains("localhost") == false else {
                continue
            }
            print("\n\(host)")
            print()
            
            // retrieve the info
            // getaddrinfo will allocate the memory, we are responsible to free it!
            var info: UnsafeMutablePointer<addrinfo>?
            defer {
                if info != nil
                {
                    freeaddrinfo(info)
                }
            }
            var status: Int32 = getaddrinfo(host, String(port), nil, &info)
            guard status == 0 else {
                print(errno, String(cString: gai_strerror(errno)))
                continue
            }
            var p = info
            var i = 0
            var ipFamily = ""
            var ipType = ""
            while p != nil {
                i += 1
                // use local copy of info
                var _info = p!.pointee
                p = _info.ai_next
                
                switch _info.ai_family {
                case PF_INET:
                    _info.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { p in
                        inet_ntop(AF_INET, &p.pointee.sin_addr, &temp, socklen_t(temp.count))
                        ipFamily = "IPv4"
                        
                    })
                    return String(cString: temp)
                case PF_INET6:
                    _info.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1, { p in
                        inet_ntop(AF_INET6, &p.pointee.sin6_addr, &temp, socklen_t(temp.count))
                        ipFamily = "IPv6"
                    })
                default:
                    continue
                }
                print(i,"\(ipFamily)\t\(String(cString: temp))", SocketType(rawValue: _info.ai_socktype)!)
                
            }
            
        }
        return ""
    }
    
    
}
