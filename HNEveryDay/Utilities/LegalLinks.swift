//
//  LegalLinks.swift
//  HNEveryDay
//
//  Created by AI on 25/10/2026.
//

import SwiftUI

enum LegalLinks {
  /// Apple's standard licensed application end user license agreement.
  static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

  /// The privacy policy ships inside the app so it is always readable, even offline.
  static var privacyPolicyURL: URL? {
    Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "html")
  }

  @ViewBuilder
  static var privacyPolicyView: some View {
    if let url = privacyPolicyURL {
      WebView(url: url)
        .navigationTitle(Text("Privacy Policy"))
        .navigationBarTitleDisplayMode(.inline)
    } else {
      Text("Privacy Policy")
    }
  }
}
