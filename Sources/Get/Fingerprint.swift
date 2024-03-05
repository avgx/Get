//
//  Fingerprint.swift
//  
//
//  Created by Alexey Govorovsky on 05.03.2024.
//

import Foundation

public protocol Fingerprint {
    var serialNumber: String { get }
    var sha256: String { get }
    var sha1: String { get }
}

func == (lhs: any Fingerprint, rhs: any Fingerprint) -> Bool {
    return lhs.serialNumber == rhs.serialNumber
    && lhs.sha256 == rhs.sha256
    && lhs.sha1 == rhs.sha1
}
