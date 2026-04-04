import Foundation

enum MockWritingAction: Hashable {
    case startDraft
    case continueWriting
    case edit
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

    static func streamedDocumentText(for request: WritingAIRequest) -> String {
        switch request.action {
        case .startDraft:
            return firstDraft(for: request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? request.project.prompt)

        case .continueWriting:
            return revisedText(
                for: request.project.documentText,
                selectedSegment: request.selectionText,
                action: .continueWriting,
                variant: .standard
            )

        case .edit:
            return revisedText(
                for: request.project.documentText,
                selectedSegment: request.selectionText,
                action: .edit,
                variant: .standard
            )
        }
    }

    static func finalDocumentText(for request: WritingAIRequest, streamedText: String) -> String {
        switch request.action {
        case .startDraft:
            return streamedText

        case .continueWriting:
            return request.project.documentText + streamedText

        case .edit:
            guard let selection = request.selectionText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !selection.isEmpty,
                  let range = request.project.documentText.range(of: selection) else {
                return request.project.documentText
            }

            var revised = request.project.documentText
            revised.replaceSubrange(range, with: streamedText)
            return revised
        }
    }

    static func streamedTextDelta(for request: WritingAIRequest) -> String {
        let finalDocumentText = streamedDocumentText(for: request)

        switch request.action {
        case .startDraft:
            return finalDocumentText

        case .continueWriting:
            return String(finalDocumentText.dropFirst(request.project.documentText.count))

        case .edit:
            guard let selection = request.selectionText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !selection.isEmpty,
                  let targetRange = request.project.documentText.range(of: selection) else {
                return finalDocumentText
            }

            let prefix = String(request.project.documentText[..<targetRange.lowerBound])
            let suffix = String(request.project.documentText[targetRange.upperBound...])
            guard finalDocumentText.hasPrefix(prefix), finalDocumentText.hasSuffix(suffix) else {
                return finalDocumentText
            }

            let lowerBound = finalDocumentText.index(finalDocumentText.startIndex, offsetBy: prefix.count)
            let upperBound = finalDocumentText.index(finalDocumentText.endIndex, offsetBy: -suffix.count)
            return String(finalDocumentText[lowerBound..<upperBound])
        }
    }

    static func streamChunks(for text: String, preferredChunkCount: Int = 3) -> [String] {
        let cleaned = text
        guard !cleaned.isEmpty else {
            return []
        }

        if cleaned.count <= 24 {
            return [cleaned]
        }

        let chunkCount = max(2, preferredChunkCount)
        let chunkSize = max(12, Int(ceil(Double(cleaned.count) / Double(chunkCount))))
        var chunks: [String] = []
        var startIndex = cleaned.startIndex

        while startIndex < cleaned.endIndex {
            let endIndex = cleaned.index(startIndex, offsetBy: chunkSize, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            chunks.append(String(cleaned[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }

    static func streamChunks(for request: WritingAIRequest) -> [String] {
        streamChunks(for: streamedTextDelta(for: request))
    }

    static func assistantLine(for action: MockWritingAction, variant: MockWritingVariant) -> String {
        switch action {
        case .startDraft:
            return "我已经根据你的方向起了一版第一稿。"
        case .continueWriting:
            return variant == .retry
                ? "我重新接着写了一段，这次把衔接再顺了一点。"
                : "我接着往下写了一段，让主线继续往前走。"
        case .edit:
            return variant == .retry
                ? "我按你选中的那段重试了一版。"
                : "我按你选中的那段改了一版。"
        }
    }

    static func assistantPrompt(for suggestion: String, mode: WritingProjectMode) -> String? {
        switch mode {
        case .discussion:
            switch suggestion {
            case "明确主题", "确认方向":
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
            case "编辑这段":
                return "我可以直接改你选中的那段。"
            case "继续写":
                return "我可以继续往下补一段，让主线往前推进。"
            case "补一段":
                return "我可以再接一段，把正文往前推进。"
            case "选中后编辑":
                return "先选中正文里要改的那一段，我就能直接改。"
            default:
                return nil
            }
        }
    }

    private static func revisedSegment(
        _ segment: String,
        action: MockWritingAction,
        variant: MockWritingVariant
    ) -> String {
        switch action {
        case .startDraft:
            return segment

        case .continueWriting:
            return variant == .retry
                ? segment + "\n\n下一段可以再轻一点，把重心慢慢往前推。"
                : segment + "\n\n接下来可以顺着这个主线，再补一段更自然的推进。"

        case .edit:
            return variant == .retry
                ? segment + " 这里可以再留一点空白。"
                : segment + " 这里不用说得太满，留白会更好。"
        }
    }

    private static func reviseWholeDocument(
        _ document: String,
        action: MockWritingAction,
        variant: MockWritingVariant
    ) -> String {
        let paragraphs = document
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !paragraphs.isEmpty else {
            return document
        }

        switch action {
        case .startDraft:
            return document

        case .continueWriting:
            let addition = variant == .retry
                ? "接下来这一段可以更安静一点，把节奏再压低些。"
                : "接下来可以顺着现在的主线，再补一段更自然的推进。"
            return document + "\n\n" + addition

        case .edit:
            var revised = paragraphs
            revised[0] = variant == .retry
                ? revised[0].replacingOccurrences(of: "未必", with: "不一定")
                : revised[0].replacingOccurrences(of: "真正", with: "确实")
            return revised.joined(separator: "\n\n")
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
}
