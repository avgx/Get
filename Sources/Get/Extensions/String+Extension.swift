//
//  String+Extension.swift
//  
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation

extension String {
    /// https://stackoverflow.com/questions/32212220/how-to-split-a-string-into-substrings-of-equal-length
    func split(by length: Int) -> [String] {
        var startIndex = self.startIndex
        var results = [Substring]()
        
        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex..<endIndex])
            startIndex = endIndex
        }
        
        return results.map { String($0) }
    }
}
