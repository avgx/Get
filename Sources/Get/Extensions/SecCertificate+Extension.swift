//
//  SecCertificate+Extension.swift
//  
//
//  Created by Alexey Govorovsky on 05.03.2024.
//

import Foundation
import CommonCrypto

extension SecCertificate {
    var isSelfSigned: Bool? {
        guard
            let subject = SecCertificateCopyNormalizedSubjectSequence(self),
            let issuer = SecCertificateCopyNormalizedIssuerSequence(self)
        else {
            return nil
        }
        return subject == issuer
    }
    
    var data: Data {
        SecCertificateCopyData(self) as Data
    }
}
