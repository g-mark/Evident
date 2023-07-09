//
//  Set+inserting.swift
//  Evident
//
//  Created by Steven Grosmark on 7/9/23.
//

import Foundation

extension Set {
    
    func inserting(_ element: Element) -> Self {
        var updated = self
        updated.insert(element)
        return updated
    }
}
