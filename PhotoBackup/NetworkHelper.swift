//
//  NetworkHelper.swift
//  PhotoBackup
//
//  Created by Lachermeier on 17.05.19.
//  Copyright © 2019 Lachermeier. All rights reserved.
//

import Foundation
import Darwin

class NetworkHelper {
    
    func getLocalIPAddress() -> String? {
        
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
        return nil
    }
    
}
