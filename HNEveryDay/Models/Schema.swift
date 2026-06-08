//
//  Schema.swift
//  HNEveryDay
//
//  Created by AI on 01/01/2026.
//

import Foundation
import SwiftData

@Model
final class CachedStory {
  @Attribute(.unique) var id: Int
  var title: String
  var url: String?
  var contentHTML: String?
  var summary: String?
  var translatedTitle: String?
  var translatedContentMarkdown: String?
  var translationLanguage: String?
  var translationUpdatedAt: Date?
  var isRead: Bool
  var isSaved: Bool
  var lastOpened: Date

  init(
    id: Int, title: String, url: String? = nil, contentHTML: String? = nil, summary: String? = nil,
    translatedTitle: String? = nil, translatedContentMarkdown: String? = nil,
    translationLanguage: String? = nil, translationUpdatedAt: Date? = nil,
    isRead: Bool = false, isSaved: Bool = false, lastOpened: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.contentHTML = contentHTML
    self.summary = summary
    self.translatedTitle = translatedTitle
    self.translatedContentMarkdown = translatedContentMarkdown
    self.translationLanguage = translationLanguage
    self.translationUpdatedAt = translationUpdatedAt
    self.isRead = isRead
    self.isSaved = isSaved
    self.lastOpened = lastOpened
  }
}
