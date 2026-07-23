//
//  KeychainHelper.swift
//  HNEveryDay
//
//  Created by AI on 02/01/2026.
//

import Foundation
import Security

enum KeychainHelper: Sendable {
  nonisolated private static let service = "com.hneveryday.app"
  
  nonisolated static func save(key: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    
    // Delete existing item first
    delete(key: key)
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data
    ]
    
    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess
  }
  
  nonisolated static func read(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    
    return String(data: data, encoding: .utf8)
  }
  
  @discardableResult
  nonisolated static func delete(key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
