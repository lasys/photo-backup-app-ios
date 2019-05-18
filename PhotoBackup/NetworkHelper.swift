//
//  NetworkHelper.swift
//  PhotoBackup
//
//  Created by Lachermeier on 17.05.19.
//  Copyright © 2019 Lachermeier. All rights reserved.
//

import Foundation
import NetUtils

class NetworkHelper {
    
    static func getLocalIPAddress() -> String? {
        let lcoalIP = Interface.allInterfaces().filter {
            $0.family == .ipv4 && $0.name == "en0"
        }
        return lcoalIP.first?.address
    }
}
