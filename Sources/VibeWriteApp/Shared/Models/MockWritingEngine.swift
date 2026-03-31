import Foundation

enum MockWritingAction: Hashable {
    case startDraft
    case expand
    case shorten
    case polish
    case selectionModify
}

enum MockWritingVariant: Hashable {
    case standard
    case retry
}

struct MockRevisionRecord: Hashable {
    let action: MockWritingAction
    let targetSegmentIndex: Int?
    let selectionText: String?
    let beforeText: String
    let afterText: String
}

enum MockWritingEngine {
    static func firstDraft(for prompt: String) -> String {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanedPrompt.contains("孤独") {
            return """
            成年人真正感到孤独的时候，未必是在深夜。
            更多时候，是在一个很普通的傍晚，手机亮了又暗，微信里有人说了几句不咸不淡的话，你礼貌地回完，然后突然意识到，自己已经很久没有真正想找谁说话。

            这种孤独并不轰烈，也不尖锐。它更像是一点点沉下来的安静，让你在忙碌里突然听见自己的声音。
            """
        }

        if cleanedPrompt.contains("雨夜") {
            return """
            雨声落得很轻，像有人在窗外慢慢敲着什么。
            她站在门口的时候，外套上还沾着一点潮气，视线刚抬起来，空气就跟着安静了半秒。

            有些重逢并不需要太多对白，只要两个人都明白，眼前这个夜晚不会轻松地过去。
            """
        }

        return """
        在你给出的方向里，最重要的不是把情绪讲满，而是先把它停在一个合适的位置。
        这篇文字先不急着给结论，而是从一个更具体的开头进入，让内容慢慢往前走。

        如果后面还要继续，我们可以围绕这个主线，再把语气收紧一点。
        """
    }

    static func revisedText(
        for document: String,
        selectedSegment: String?,
        action: MockWritingAction,
        variant: MockWritingVariant
    ) -> String {
        if let selectedSegment {
            return replaceSelectedSegment(
                in: document,
                target: selectedSegment,
                with: revisedSegment(selectedSegment, action: action, variant: variant)
            )
        }

        return reviseWholeDocument(document, action: action, variant: variant)
    }

    static func assistantLine(for action: MockWritingAction, variant: MockWritingVariant) -> String {
        switch action {
        case .startDraft:
            return "我已经根据你的方向起了一版第一稿。"
        case .expand:
            return variant == .retry
                ? "我又试了一版扩写，节奏更松一点。"
                : "我把这段往外展开了一点，情绪还保持在当前主线内。"
        case .shorten:
            return variant == .retry
                ? "我重新收了一遍，这次更短更稳。"
                : "我把这段收紧了一些，删掉了多余解释。"
        case .polish:
            return variant == .retry
                ? "我又磨了一遍语气，让它更贴近当前风格。"
                : "我把这段润了一下，语气更平一点。"
        case .selectionModify:
            return variant == .retry
                ? "我按你选中的那段重试了一版。"
                : "我按你选中的那段改了一版。"
        }
    }

    static func assistantPrompt(for suggestion: String, mode: WritingProjectMode) -> String? {
        switch mode {
        case .discussion:
            switch suggestion {
            case "明确主题":
                return "你可以先告诉我这篇内容最想写的主题是什么。"
            case "确认语气":
                return "你希望它更克制一点，还是更偏个人化一点？"
            case "开始起稿":
                return nil
            default:
                return nil
            }

        case .collaboration:
            switch suggestion {
            case "调整语气":
                return "我可以先把这段语气再压低一点。"
            case "继续展开":
                return "我可以继续往下补一段，让主线往前推进。"
            case "收紧结尾":
                return "我可以把结尾再收一收，让落点更轻。"
            case "降低解释感":
                return "我可以把解释感再降一点，让内容更克制。"
            default:
                return nil
            }
        }
    }

    private static func revisedSegment(_ segment: String, action: MockWritingAction, variant: MockWritingVariant) -> String {
        switch action {
        case .expand:
            return variant == .retry
                ? segment + " 这也给后面的内容留出了一点更自然的余地。"
                : segment + " 这样处理之后，后面的情绪可以慢慢再往外延伸。"

        case .shorten:
            let core = shortestSentence(from: segment)
            return variant == .retry
                ? core + "，其余内容可以先收起来。"
                : core + "，这样更干净一些。"

        case .polish:
            return variant == .retry
                ? segment.replacingOccurrences(of: "很", with: "稍微").replacingOccurrences(of: "一点", with: "一些")
                : segment.replacingOccurrences(of: "更", with: "稍微更")

        case .selectionModify:
            return variant == .retry
                ? segment + " 这里可以再留一点空白。"
                : segment + " 这里不用说得太满，留白会更好。"

        case .startDraft:
            return segment
        }
    }

    private static func reviseWholeDocument(_ document: String, action: MockWritingAction, variant: MockWritingVariant) -> String {
        let paragraphs = document
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !paragraphs.isEmpty else { return document }

        switch action {
        case .expand:
            let addition = variant == .retry
                ? "这一层意思可以继续往后延伸，但仍然不需要一下子说透。"
                : "如果继续往下写，可以让内容再向前多走半步，让节奏更自然。"
            return document + "\n\n" + addition

        case .shorten:
            if paragraphs.count > 1 {
                return paragraphs.dropLast().joined(separator: "\n\n")
            }
            return shortestSentence(from: document)

        case .polish:
            var revised = paragraphs
            revised[0] = variant == .retry
                ? revised[0].replacingOccurrences(of: "未必", with: "不一定")
                : revised[0].replacingOccurrences(of: "真正", with: "确实")
            return revised.joined(separator: "\n\n")

        case .selectionModify:
            return variant == .retry
                ? document + "\n\n这里可以再留一点空白。"
                : document + "\n\n这里不用说得太满。"

        case .startDraft:
            return document
        }
    }

    private static func replaceSelectedSegment(in document: String, target: String, with replacement: String) -> String {
        guard let range = document.range(of: target) else {
            return document
        }

        var copy = document
        copy.replaceSubrange(range, with: replacement)
        return copy
    }

    private static func shortestSentence(from text: String) -> String {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = sentences.first {
            return first + "。"
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
