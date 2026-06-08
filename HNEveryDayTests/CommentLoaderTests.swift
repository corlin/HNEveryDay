//
//  CommentLoaderTests.swift
//  HNEveryDayTests
//
//  Created by AI on 06/08/2026.
//

import XCTest
@testable import HNEveryDay

final class CommentLoaderTests: XCTestCase {
  func testLoadCommentsSkipsDeletedAndDeadItemsAndPreservesRequestedOrder() async throws {
    let client = StubCommentClient(
      items: [
        1: commentItem(id: 1),
        2: commentItem(id: 2, deleted: true),
        3: commentItem(id: 3, dead: true),
        4: commentItem(id: 4),
      ],
      reverseEachBatch: true
    )
    let loader = CommentLoader(client: client)

    let nodes = try await loader.loadComments(for: [1, 2, 3, 4])

    XCTAssertEqual(nodes.map(\.id), [1, 4])
  }

  func testLoadCommentsRecursivelyLoadsChildrenWithDepth() async throws {
    let client = StubCommentClient(
      items: [
        1: commentItem(id: 1, kids: [2, 3]),
        2: commentItem(id: 2, kids: [4]),
        3: commentItem(id: 3),
        4: commentItem(id: 4),
      ]
    )
    let loader = CommentLoader(client: client)

    let nodes = try await loader.loadComments(for: [1])

    XCTAssertEqual(nodes.map(\.id), [1])
    XCTAssertEqual(nodes[0].depth, 0)
    XCTAssertEqual(nodes[0].children.map(\.id), [2, 3])
    XCTAssertEqual(nodes[0].children.map(\.depth), [1, 1])
    XCTAssertEqual(nodes[0].children[0].children.map(\.id), [4])
    XCTAssertEqual(nodes[0].children[0].children[0].depth, 2)
  }

  func testLoadCommentsUsesCacheForRepeatedIds() async throws {
    let client = CountingCommentClient(
      items: [
        1: commentItem(id: 1)
      ]
    )
    let loader = CommentLoader(client: client)

    let firstLoad = try await loader.loadComments(for: [1])
    let secondLoad = try await loader.loadComments(for: [1])
    let requestedIds = await client.requestedIds

    XCTAssertEqual(firstLoad.map(\.id), [1])
    XCTAssertEqual(secondLoad.map(\.id), [1])
    XCTAssertEqual(requestedIds, [1])
  }
}

private struct StubCommentClient: HNCommentFetching {
  let items: [Int: HNItem]
  var reverseEachBatch = false

  func fetchItems(ids: [Int]) async throws -> [HNItem] {
    let result = ids.compactMap { items[$0] }
    if reverseEachBatch {
      return Array(result.reversed())
    }
    return result
  }
}

private actor CountingCommentClient: HNCommentFetching {
  let items: [Int: HNItem]
  private var requests: [Int] = []

  init(items: [Int: HNItem]) {
    self.items = items
  }

  var requestedIds: [Int] {
    requests
  }

  func fetchItems(ids: [Int]) async throws -> [HNItem] {
    requests.append(contentsOf: ids)
    return ids.compactMap { items[$0] }
  }
}

private func commentItem(
  id: Int,
  kids: [Int]? = nil,
  deleted: Bool? = nil,
  dead: Bool? = nil
) -> HNItem {
  HNItem(
    id: id,
    type: .comment,
    by: "user\(id)",
    time: Date(timeIntervalSince1970: Double(id)),
    text: "Comment \(id)",
    url: nil,
    score: nil,
    title: nil,
    descendants: nil,
    kids: kids,
    parent: nil,
    deleted: deleted,
    dead: dead
  )
}
