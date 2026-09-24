// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum ContentType: String, Codable, CaseIterable {
    case text
    case richText
    case image
    case video
    case file
    case fileStack

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .video: return "Video"
        case .file: return "File"
        case .fileStack: return "Files"
        }
    }

    var systemImageName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "text.badge.star"
        case .image: return "photo"
        case .video: return "video"
        case .file: return "doc"
        case .fileStack: return "doc.on.doc"
        }
    }
}
