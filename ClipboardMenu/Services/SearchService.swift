import Foundation

@MainActor
class SearchService {
    func search(items: [ClipboardItem], query: String, useRegex: Bool) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }

        if useRegex {
            return regexSearch(items: items, pattern: query)
        } else {
            return plainTextSearch(items: items, query: query)
        }
    }

    func search(snippets: [Snippet], query: String, useRegex: Bool) -> [Snippet] {
        guard !query.isEmpty else { return snippets }

        if useRegex {
            return regexSearch(snippets: snippets, pattern: query)
        } else {
            return plainTextSearch(snippets: snippets, query: query)
        }
    }

    private func plainTextSearch(items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let lowercasedQuery = query.lowercased()
        return items.filter { item in
            if let text = item.textContent?.lowercased() {
                return text.contains(lowercasedQuery)
            }
            return false
        }
    }

    private func plainTextSearch(snippets: [Snippet], query: String) -> [Snippet] {
        let lowercasedQuery = query.lowercased()
        return snippets.filter { snippet in
            if snippet.name.lowercased().contains(lowercasedQuery) {
                return true
            }
            if let text = snippet.textContent?.lowercased() {
                return text.contains(lowercasedQuery)
            }
            return false
        }
    }

    private func regexSearch(items: [ClipboardItem], pattern: String) -> [ClipboardItem] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            // Invalid regex, fall back to plain text
            return plainTextSearch(items: items, query: pattern)
        }

        return items.filter { item in
            guard let text = item.textContent else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    private func regexSearch(snippets: [Snippet], pattern: String) -> [Snippet] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            // Invalid regex, fall back to plain text
            return plainTextSearch(snippets: snippets, query: pattern)
        }

        return snippets.filter { snippet in
            // Check name
            let nameRange = NSRange(snippet.name.startIndex..., in: snippet.name)
            if regex.firstMatch(in: snippet.name, options: [], range: nameRange) != nil {
                return true
            }

            // Check content
            guard let text = snippet.textContent else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    func filterByContentType(items: [ClipboardItem], types: Set<ContentType>) -> [ClipboardItem] {
        guard !types.isEmpty else { return items }
        return items.filter { types.contains($0.contentType) }
    }

    func filterByContentType(snippets: [Snippet], types: Set<ContentType>) -> [Snippet] {
        guard !types.isEmpty else { return snippets }
        return snippets.filter { types.contains($0.contentType) }
    }

    // Highlight matches in text for display
    func highlightMatches(in text: String, query: String, useRegex: Bool) -> [(range: Range<String.Index>, isMatch: Bool)] {
        guard !query.isEmpty else {
            return [(text.startIndex..<text.endIndex, false)]
        }

        var results: [(Range<String.Index>, Bool)] = []

        if useRegex {
            guard let regex = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) else {
                return [(text.startIndex..<text.endIndex, false)]
            }

            let nsRange = NSRange(text.startIndex..., in: text)
            var lastEnd = text.startIndex

            regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
                guard let match = match,
                      let range = Range(match.range, in: text) else { return }

                if lastEnd < range.lowerBound {
                    results.append((lastEnd..<range.lowerBound, false))
                }
                results.append((range, true))
                lastEnd = range.upperBound
            }

            if lastEnd < text.endIndex {
                results.append((lastEnd..<text.endIndex, false))
            }
        } else {
            let lowercasedText = text.lowercased()
            let lowercasedQuery = query.lowercased()
            var searchStart = text.startIndex
            var lastEnd = text.startIndex

            while let range = lowercasedText.range(of: lowercasedQuery, range: searchStart..<lowercasedText.endIndex) {
                // Convert to original text indices
                let originalRange = text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound))

                if lastEnd < originalRange.lowerBound {
                    results.append((lastEnd..<originalRange.lowerBound, false))
                }
                results.append((originalRange, true))
                lastEnd = originalRange.upperBound
                searchStart = range.upperBound
            }

            if lastEnd < text.endIndex {
                results.append((lastEnd..<text.endIndex, false))
            }
        }

        return results.isEmpty ? [(text.startIndex..<text.endIndex, false)] : results
    }
}
