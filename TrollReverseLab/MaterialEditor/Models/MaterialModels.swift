import Foundation
import UIKit

// MARK: - Platform Template

/// Predefined format templates for different content platforms.
/// Used for personal original content formatting only — no auto-posting.
struct PlatformTemplate: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let iconName: String
    let aspectRatio: CGFloat      // width / height
    let maxTextLength: Int
    let recommendedImageSize: String
    let description: String
    let hashtagHint: String

    static let allTemplates: [PlatformTemplate] = [
        PlatformTemplate(
            id: "general_square",
            name: "通用方形",
            iconName: "square",
            aspectRatio: 1.0,
            maxTextLength: 500,
            recommendedImageSize: "1080 x 1080",
            description: "适用于朋友圈、Instagram 等方形图片场景",
            hashtagHint: "建议 3-5 个标签"
        ),
        PlatformTemplate(
            id: "weibo_timeline",
            name: "微博横版",
            iconName: "rectangle",
            aspectRatio: 16.0 / 9.0,
            maxTextLength: 140,
            recommendedImageSize: "1080 x 608",
            description: "微博横版图文，140 字以内",
            hashtagHint: "#话题# 格式"
        ),
        PlatformTemplate(
            id: "xiaohongshu_vertical",
            name: "小红书竖版",
            iconName: "rectangle.portrait",
            aspectRatio: 3.0 / 4.0,
            maxTextLength: 1000,
            recommendedImageSize: "1080 x 1440",
            description: "小红书 3:4 竖版图片，长文案",
            hashtagHint: "建议 5-10 个标签"
        ),
        PlatformTemplate(
            id: "short_video_vertical",
            name: "短视频竖版",
            iconName: "play.rectangle.fill",
            aspectRatio: 9.0 / 16.0,
            maxTextLength: 300,
            recommendedImageSize: "1080 x 1920",
            description: "抖音/快手 9:16 竖版封面",
            hashtagHint: "建议 3-5 个标签"
        ),
        PlatformTemplate(
            id: "article_banner",
            name: "文章横幅",
            iconName: "doc.richtext",
            aspectRatio: 2.35,
            maxTextLength: 2000,
            recommendedImageSize: "1080 x 460",
            description: "公众号/博客文章横幅图片",
            hashtagHint: "无需标签"
        ),
        PlatformTemplate(
            id: "landscape_wide",
            name: "横版宽屏",
            iconName: "rectangle.split.3x1",
            aspectRatio: 16.0 / 9.0,
            maxTextLength: 800,
            recommendedImageSize: "1920 x 1080",
            description: "通用横版宽屏图文",
            hashtagHint: "建议 3-5 个标签"
        )
    ]
}

// MARK: - Material Project

/// A single material project for personal original content.
struct MaterialProject: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var platformId: String
    var imageFileName: String?      // stored in materials directory
    var tags: [String]
    var status: MaterialStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        title: String = "",
        content: String = "",
        platformId: String = "general_square",
        imageFileName: String? = nil,
        tags: [String] = [],
        status: MaterialStatus = .draft
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.platformId = platformId
        self.imageFileName = imageFileName
        self.tags = tags
        self.status = status
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var platform: PlatformTemplate? {
        PlatformTemplate.allTemplates.first { $0.id == platformId }
    }

    var characterCount: Int {
        content.count
    }

    var isOverLimit: Bool {
        guard let p = platform else { return false }
        return content.count > p.maxTextLength
    }
}

// MARK: - Material Status

enum MaterialStatus: String, Codable, CaseIterable {
    case draft = "draft"
    case refining = "refining"
    case ready = "ready"
    case published = "published"  // manually published by user

    var displayName: String {
        switch self {
        case .draft: return "草稿"
        case .refining: return "润色中"
        case .ready: return "待发布"
        case .published: return "已发布"
        }
    }

    var iconName: String {
        switch self {
        case .draft: return "doc.text"
        case .refining: return "wand.and.stars"
        case .ready: return "checkmark.circle"
        case .published: return "paperplane.fill"
        }
    }

    var color: String {
        switch self {
        case .draft: return "gray"
        case .refining: return "orange"
        case .ready: return "blue"
        case .published: return "green"
        }
    }
}

// MARK: - AI Refinement Options

enum RefinementStyle: String, CaseIterable {
    case polish = "polish"
    case shorten = "shorten"
    case expand = "expand"
    case reformat = "reformat"
    case hashtagSuggest = "hashtag"

    var displayName: String {
        switch self {
        case .polish: return "润色优化"
        case .shorten: return "精简压缩"
        case .expand: return "扩写丰富"
        case .reformat: return "排版整理"
        case .hashtagSuggest: return "标签推荐"
        }
    }

    var iconName: String {
        switch self {
        case .polish: return "sparkles"
        case .shorten: return "scissors"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .reformat: return "text.alignleft"
        case .hashtagSuggest: return "number"
        }
    }

    var promptInstruction: String {
        switch self {
        case .polish:
            return "请润色以下原创文案，改善语言表达，使其更加流畅自然，保持原意不变。"
        case .shorten:
            return "请精简以下文案，保留核心信息，删除冗余内容，使其更加简洁有力。"
        case .expand:
            return "请基于以下文案的核心主题，适当扩写丰富内容，增加细节描述和情感表达。"
        case .reformat:
            return "请重新排版以下文案，添加合适的段落分隔、标点符号和表情符号，使其更易阅读。"
        case .hashtagSuggest:
            return "请根据以下文案内容，推荐 5-10 个相关的标签关键词，以 # 开头，用空格分隔。"
        }
    }
}
