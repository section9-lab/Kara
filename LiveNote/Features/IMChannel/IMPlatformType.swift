import Foundation

/// Supported IM platform types.
enum IMPlatformType: String, CaseIterable, Identifiable, Codable {
    case wechat
    case dingtalk
    case feishu
    case wecom       // 企业微信
    case slack
    case telegram

    static var visibleIMCases: [IMPlatformType] {
        [.wechat, .feishu]
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wechat:    return "微信"
        case .dingtalk:  return "钉钉"
        case .feishu:    return "飞书"
        case .wecom:     return "企业微信"
        case .slack:     return "Slack"
        case .telegram:  return "Telegram"
        }
    }

    var iconSystemName: String {
        switch self {
        case .wechat:    return "bubble.left.and.bubble.right.fill"
        case .dingtalk:  return "message.fill"
        case .feishu:    return "paperplane.fill"
        case .wecom:     return "bubble.left.and.bubble.right.fill"
        case .slack:     return "number"
        case .telegram:  return "airplane"
        }
    }

    /// Placeholder text for webhook URL input.
    var webhookPlaceholder: String {
        switch self {
        case .wechat:    return "打开微信后扫码登录并进入对话"
        case .dingtalk:  return "https://oapi.dingtalk.com/robot/send?access_token=..."
        case .feishu:    return "https://open.feishu.cn/open-apis/bot/v2/hook/..."
        case .wecom:     return "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=..."
        case .slack:     return "https://hooks.slack.com/services/..."
        case .telegram:  return "Bot Token (e.g. 123456:ABC-DEF...)"
        }
    }
}
