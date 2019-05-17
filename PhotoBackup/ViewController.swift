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
import JGProgressHUD


class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate{

    @IBOutlet weak var uploadButton: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var infoLabel: UILabel!
    
    var hud = JGProgressHUD(style: .dark)
    
    let network = NetworkHelper()
    var serverIP = ""
    let semaphore = DispatchSemaphore(value: 0)
    
    var counter = 0
    var total = 0
    var errorOccured = false
    var isBackupRunning = false
    var cancelBackup = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.numberOfTapsRequired = 2
        self.view.addGestureRecognizer(tap)
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        displayNumberOfAvailablePhotos()
        checkIfServerIPIsAvailable()
    }
    
    // MARK: - Server Finding
    
    func findServer() {
        guard let localIP = network.getLocalIPAddress() else {
            self.localIPNotFound()
            return
        }
        
        let präfix = localIP.split(separator: ".").dropLast().joined(separator: ".")
        
        for suffix in 1...255 {
            let tmpIP = "\(präfix).\(suffix)"
            findServerRequest(ip: tmpIP, completion: { response in
                if (response) {
                    self.serverIP = tmpIP
                    self.serverFound(ip: tmpIP)
                }
            })
        }
    }
    
    func findServerRequest(ip: String, completion: @escaping (Bool) -> Void){
        let url = "http://\(ip):8080/backup"
        Alamofire.request(url).responseJSON(completionHandler: { response in
            switch response.response?.statusCode {
                case 204:
                    completion(true)
                default:
                    completion(false)
            }
        })
    }
    
    // MARK: - Upload (Requests)
    
    func callExistsRequest(name: String, timestamp: Int64, completion: @escaping (Bool?) -> Void) {
        Alamofire.request("http://\(serverIP):8080/exists", parameters: ["name": name, "timestamp":timestamp])
            .responseJSON(completionHandler: {response in
                switch response.response?.statusCode {
                case 404:
                    print("not found")
                    completion(false)
                case 200:
                    print("ok")
                    completion(true)
                case 400:
                    print("bad request")
                    completion(nil)
                default:
                    print("other status code: \(String(describing: response.response?.statusCode))")
                    completion(nil)
                }
          })
    }
    
    
    func callUploadRequest(imgURL: URL, timestamp: Int64, completion: @escaping (Bool) -> Void) {
        
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
         to: "http://\(serverIP):8080/image",
         encodingCompletion: { encodingResult in

            switch encodingResult {
            case .success(let upload, _, _):
                upload.responseJSON { response in
                    guard let statusCode = response.response?.statusCode else  {
                        print("Something went wrong while uploading: response is nul!");
                        completion(false);
                        return
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
                completion(false)
            }
        })
    }
    
    
    func startUpload() {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized:
                let fetchOptions = PHFetchOptions()
                let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                self.total = allPhotos.count
                self.counter = 0
                self.errorOccured = false
                self.isBackupRunning = true
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
                           self.errorOccuredWhileUploading()
                        }
                        return
                    }
                    
                    if (self.cancelBackup) {
                        DispatchQueue.main.async {
                            self.backupWasCanceled()
                        }
                        return
                    }
                    
//                    sleep(2)
                    let image:PHAsset = allPhotos.object(at: index)
                    
                    image.requestContentEditingInput(with: PHContentEditingInputRequestOptions(), completionHandler: { (eidtingInput, info) in
                        if let input = eidtingInput, let imgURL = input.fullSizeImageURL {
                            let timestamp = Int64((image.creationDate!.timeIntervalSince1970) * 1000)
                            self.callExistsRequest(name: "\(imgURL.absoluteString.split(separator: "/").last!)", timestamp: timestamp,  completion: { result in
                                guard let exists = result else {
                                    self.errorOccured = true
                                    self.semaphore.signal()
                                    return
                                }
                                if (exists == false) {
                                    print("Image not existing - upload")
                                    self.callUploadRequest(imgURL: imgURL, timestamp: timestamp, completion: { result in
                                        if result {
                                           
                                            DispatchQueue.main.async {
                                                 self.counter += 1
                                                if index == allPhotos.count - 1 {
                                                        self.finishedBackup()
                                                } else {
                                                    self.updateHUD()
                                                }
                                               
                                            }
                                        } else {
                                            DispatchQueue.main.async {
                                                self.errorOccured = true
                                            }
                                        }
                                        self.semaphore.signal()
                                    })
                                } else {
                                    
                                    DispatchQueue.main.async {
                                        self.counter += 1
                                        if index == allPhotos.count - 1 {
                                            self.finishedBackup()
                                        } else {
                                            self.updateHUD()
                                        }
                                    }
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
    
    // MARK: - UI Handler
    
    
    @objc func handleTap(sender: UITapGestureRecognizer? = nil) {
        if !isBackupRunning {
            return
        }
        self.showShouldCancelAlert()
    }
    
    @IBAction func button(_ sender: Any) {
        showBackupStartHUD()
        self.infoLabel.text = "Doppeltap, um Vorgang abzubrechen."
        self.startUpload()
    }
    
    
    
    // MARK: - HUD Helper
    
    
    func showBackupStartHUD() {
        self.hud = JGProgressHUD(style: .dark)
        self.hud.vibrancyEnabled = true
        self.hud.textLabel.text = "Backup läuft"
        self.hud.detailTextLabel.text = "\(counter) von \(total) hochgeladen"
        self.hud.show(in: self.view)
    }
    
    func finishedBackup() {
        UIView.animate(withDuration: 0.1, animations: {
            self.hud.textLabel.text = "Backup abgeschlossen!"
            self.hud.detailTextLabel.text = nil
            self.hud.indicatorView = JGProgressHUDSuccessIndicatorView()
            self.hud.dismiss(afterDelay: 3, animated: true)
        })
        self.infoLabel.text = "\(counter) Bilder wurden erfolgreich gesichert."
        self.resetVarsBeforeUploading()
    }
    
    func updateHUD() {
        self.hud.detailTextLabel.text = "\(counter) von \(total) hochgeladen"
    }
    
    func backupWasCanceled() {
        UIView.animate(withDuration: 0.1, animations: {
            self.hud.textLabel.text = "Backup abgebrochen!"
            self.hud.detailTextLabel.text = nil
            self.hud.indicatorView = JGProgressHUDErrorIndicatorView()
            self.hud.dismiss(afterDelay: 3, animated: true)
        })
        self.infoLabel.text = "Backup wurde abgebrochen."
        self.resetVarsBeforeUploading()
    }
    
    func errorOccuredWhileUploading() {
        UIView.animate(withDuration: 0.1, animations: {
            self.hud.textLabel.text = "Backup unerwartet beendet!"
            self.hud.detailTextLabel.text = nil
            self.hud.indicatorView = JGProgressHUDErrorIndicatorView()
            self.hud.dismiss(afterDelay: 3, animated: true)
        })
        self.infoLabel.text = "\(self.counter) von \(self.total): Fehler beim Hochladen!"
        self.resetVarsBeforeUploading()
    }
    
    func localIPNotFound() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.1, animations: {
                self.hud.textLabel.text = "IP Adresse nicht gefunden!"
                self.hud.detailTextLabel.text = "Starte die App erneut."
                self.hud.indicatorView = JGProgressHUDErrorIndicatorView()
                self.hud.dismiss(afterDelay: 5, animated: true)
            })
        }
    }
    
    func serverFound(ip: String) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.1, animations: {
                self.hud.textLabel.text = "Server gefunden"
                self.hud.detailTextLabel.text = "IP: \(ip)"
                self.hud.indicatorView = JGProgressHUDSuccessIndicatorView()
                self.hud.dismiss(afterDelay: 1, animated: true)
            })
            self.uploadButton.isEnabled = true
        }
    }
    
    func showServerSearchingHUD() {
        self.hud.vibrancyEnabled = true
        self.hud.textLabel.text = "Suche Server"
        self.hud.show(in: self.view)
    }
    
    // MARK: - Helper Methods
    
    func resetVarsBeforeUploading() {
        self.isBackupRunning = false
        self.uploadButton.isEnabled = true
        self.cancelBackup = false
        self.errorOccured = false
        self.counter = 0
    }
    
    func checkIfServerIPIsAvailable() {
        if (serverIP == "") {
            self.showServerSearchingHUD()
            DispatchQueue.global().async {
                self.findServer()
            }
            self.uploadButton.isEnabled = false
        }
    }
    
    func displayNumberOfAvailablePhotos() {
        DispatchQueue.global().async {
            PHPhotoLibrary.requestAuthorization { status in
                switch status {
                case .authorized:
                    let fetchOptions = PHFetchOptions()
                    let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                    DispatchQueue.main.sync {
                        self.total = allPhotos.count
                        self.infoLabel.text = "\(self.total) Bilder gefunden"
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
    
    func showShouldCancelAlert() {
        let alertController = UIAlertController(title: "Backup abbrechen?", message: "", preferredStyle: .alert)
        let actionYes = UIAlertAction(title: "Ja", style: .destructive) { (action:UIAlertAction) in
            self.cancelBackup = true
        }
        let actionNo = UIAlertAction(title: "Nein", style: .cancel) { (action:UIAlertAction) in
        }
        alertController.addAction(actionYes)
        alertController.addAction(actionNo)
        self.present(alertController, animated: true)
    }
    
}
