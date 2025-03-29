//
//  User.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import Foundation

struct User: Identifiable, Codable {
    var id: String
    var email: String
    var name: String
    var profileImageURL: String?
}
