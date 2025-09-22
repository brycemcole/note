import Foundation
import CoreFoundation
#if canImport(WebKit)
import WebKit
#endif

private actor WebFetchThrottler {
    private var lastURLString: String?
    private var lastHost: String?
    private var lastFetchByHost: [String: Date] = [:]
    private let sameURLDelay: TimeInterval = 1.0
    private let consecutiveHostDelay: TimeInterval = 0.6
    private let minimumSpacingPerHost: TimeInterval = 0.4

    func waitIfNeeded(for url: URL) async {
        let host = url.host ?? ""

        if let previousURL = lastURLString, previousURL == url.absoluteString {
            try? await Task.sleep(nanoseconds: UInt64(sameURLDelay * 1_000_000_000))
        } else if let previousHost = lastHost, previousHost == host {
            try? await Task.sleep(nanoseconds: UInt64(consecutiveHostDelay * 1_000_000_000))
        } else if let last = lastFetchByHost[host] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minimumSpacingPerHost {
                try? await Task.sleep(nanoseconds: UInt64((minimumSpacingPerHost - elapsed) * 1_000_000_000))
            }
        }

        lastURLString = url.absoluteString
        lastHost = host
        lastFetchByHost[host] = Date()
    }
}

enum WebFetchError: Error, Equatable {
    case invalidResponse
    case badStatus(Int)
    case emptyPayload
    case javaScriptRenderingUnavailable
    case javaScriptExecutionFailed
}

enum WebFetcher {
    private static let throttler = WebFetchThrottler()
    private static let retryableStatusCodes: Set<Int> = [403, 408, 429, 500, 502, 503, 504]

    static func fetchHTML(from url: URL,
                          maxAttempts: Int = 3,
                          preferJavaScriptRendering: Bool = true,
                          javaScriptWaitDuration: TimeInterval = 4.5) async throws -> String {
        var renderingError: Error?

        if preferJavaScriptRendering {
            do {
                print("🌐 WebFetcher: Attempting JS-rendered load for \(url.absoluteString)")
                if let rendered = try await fetchRenderedHTMLIfAvailable(from: url, waitAfterLoad: javaScriptWaitDuration),
                   !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("✅ WebFetcher: JS-rendered HTML loaded (length: \(rendered.count)) for \(url.host ?? url.absoluteString)")
                    return rendered
                }
            } catch {
                print("⚠️ WebFetcher: JS-rendered load failed for \(url.absoluteString) with error: \(error)")
                if let webError = error as? WebFetchError, webError == .javaScriptRenderingUnavailable {
                    renderingError = nil
                } else {
                    renderingError = error
                }
            }
        }

        do {
            print("🌐 WebFetcher: Falling back to static fetch for \(url.absoluteString)")
            return try await fetchStaticHTML(from: url, maxAttempts: maxAttempts)
        } catch {
            if let renderingError {
                throw renderingError
            }
            throw error
        }
    }

    private static func fetchStaticHTML(from url: URL, maxAttempts: Int) async throws -> String {
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            attempt += 1
            await throttler.waitIfNeeded(for: url)

            var request = URLRequest(url: url)
            request.timeoutInterval = 20

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw WebFetchError.invalidResponse
                }

                if (200..<300).contains(http.statusCode) {
                    if data.isEmpty { throw WebFetchError.emptyPayload }
                    let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    print("✅ WebFetcher: Static HTML loaded (length: \(html.count)) for \(url.host ?? url.absoluteString)")
                    return html
                }

                lastError = WebFetchError.badStatus(http.statusCode)

                if shouldRetry(statusCode: http.statusCode, attempt: attempt, maxAttempts: maxAttempts) {
                    let backoff = backoffDelay(forAttempt: attempt)
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                } else {
                    throw WebFetchError.badStatus(http.statusCode)
                }
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    let backoff = backoffDelay(forAttempt: attempt)
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                } else {
                    throw error
                }
            }
        }

        throw lastError ?? WebFetchError.invalidResponse
    }

    private static func fetchRenderedHTMLIfAvailable(from url: URL, waitAfterLoad: TimeInterval) async throws -> String? {
#if canImport(WebKit)
        if #available(iOS 17.0, macOS 14.0, macCatalyst 17.0, visionOS 1.0, *) {
            return try await WebPageRenderer.shared.renderHTML(from: url, waitAfterLoad: waitAfterLoad)
        } else {
            throw WebFetchError.javaScriptRenderingUnavailable
        }
#else
        throw WebFetchError.javaScriptRenderingUnavailable
#endif
    }

    private static func shouldRetry(statusCode: Int, attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        return retryableStatusCodes.contains(statusCode)
    }

    private static func backoffDelay(forAttempt attempt: Int) -> UInt64 {
        let base = pow(2.0, Double(attempt - 1)) * 0.6
        let jitter = Double.random(in: -0.15...0.15)
        let delay = max(0.3, base + jitter)
        return UInt64(delay * 1_000_000_000)
    }
}

#if canImport(WebKit)
@MainActor
private final class WebPageRenderer {
    static let shared = WebPageRenderer()

    private init() {}

    /// Loads the URL in a headless WebPage, waits briefly for JavaScript execution, and returns the rendered HTML.
    func renderHTML(from url: URL, waitAfterLoad: TimeInterval) async throws -> String {
        var configuration = WebPage.Configuration()
        configuration.loadsSubresources = true
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()

        let page = WebPage(configuration: configuration)
        page.customUserAgent = Self.desktopUserAgent

        let request = URLRequest(url: url)
        for try await _ in page.load(request) {}

        if waitAfterLoad > 0 {
            try await Task.sleep(nanoseconds: UInt64(waitAfterLoad * 1_000_000_000))
        }

        let script = "document.documentElement ? document.documentElement.outerHTML : document.body ? document.body.outerHTML : ''"
        guard let html = try await page.callJavaScript(script) as? String else {
            throw WebFetchError.javaScriptExecutionFailed
        }

        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WebFetchError.emptyPayload
        }

        return html
    }

    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
#endif

struct LinkMetadata {
    enum Kind: String {
        case general
        case product
    }

    var kind: Kind = .general
    var productName: String?
    var price: String?
    var currency: String?
    var availability: String?
    var isInStock: Bool?
}

// Extract the <title> content from an HTML string
func extractHTMLTitle(from html: String) -> String? {
    let pattern = #"<title[^>]*>(.*?)</title>"#
    let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    let range = NSRange(location: 0, length: html.utf16.count)
    guard let match = regex?.firstMatch(in: html, options: [], range: range),
          let r = Range(match.range(at: 1), in: html) else { return nil }
    return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
}

// Extract a meta description from HTML if present
func extractHTMLMetaDescription(from html: String) -> String? {
    let range = NSRange(location: 0, length: html.utf16.count)
    let metaPattern = #"<meta[^>]*name=[\"']description[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
    let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive])
    if let match = metaRegex?.firstMatch(in: html, options: [], range: range),
       let r = Range(match.range(at: 1), in: html) {
        let description = String(html[r])
            .htmlDecoded
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }
    return nil
}

// Best-effort image extraction from HTML
func extractBestImageURL(from html: String, baseURL: URL) -> String? {
    // 1) Domain-specific: YouTube best thumbnail
    if let yt = extractYouTubeThumbnailURL(from: baseURL, html: html) { return yt }

    // 2) Aggregate candidates from multiple sources
    var candidates: [(url: String, width: Int?, height: Int?)] = []

    // Open Graph / Twitter (with sizes if available)
    candidates.append(contentsOf: extractMetaImageCandidates(from: html))

    // JSON-LD images
    for u in extractJSONLDImageURLs(from: html) {
        candidates.append((u, nil, nil))
    }

    // <img> tags (src/srcset/data-src)
    candidates.append(contentsOf: extractImgTagCandidates(from: html).map { ($0.0, $0.1, nil) })

    // Normalize, filter logos/placeholders, and score
    let skipPatterns: [String] = ["logo", "favicon", "sprite", "avatar", "placeholder", "og-logo", "yt_icon"]

    var scored: [(url: String, score: Int)] = []
    for (rawURL, w, h) in candidates {
        guard let normalized = normalizeImageURL(rawURL, baseURL: baseURL) else { continue }
        let lower = normalized.lowercased()
        if skipPatterns.contains(where: { lower.contains($0) }) { continue }
        let s = scoreImageURL(normalized, width: w, height: h)
        scored.append((normalized, s))
    }

    if let best = bestImageURL(from: scored, baseURL: baseURL) { return best }

    // Fallback: previous simple methods
    if let og = extractOpenGraphImage(from: html, baseURL: baseURL) { return og }
    if let tw = extractTwitterCardImage(from: html, baseURL: baseURL) { return tw }
    return extractFirstImageURL(from: html, baseURL: baseURL)
}

func extractLinkMetadata(from html: String, baseURL: URL) -> LinkMetadata {
    var metadata = LinkMetadata()

    let (price, currency) = extractHTMLPrice(from: html)
    metadata.price = price?.trimmingCharacters(in: .whitespacesAndNewlines)
    metadata.currency = currency?.trimmingCharacters(in: .whitespacesAndNewlines)

    metadata.productName = extractProductName(from: html)?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines)

    let availabilityInfo = extractAvailabilityInfo(from: html)
    metadata.availability = availabilityInfo.text

    if isProductLike(html: html, baseURL: baseURL, hasPrice: metadata.price != nil, availability: metadata.availability) {
        metadata.kind = .product
        metadata.isInStock = availabilityInfo.inStock ?? true
        if metadata.productName == nil {
            metadata.productName = extractHTMLTitle(from: html)?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } else {
        metadata.isInStock = availabilityInfo.inStock
    }

    return metadata
}

private func bestImageURL(from scored: [(url: String, score: Int)], baseURL: URL) -> String? {
    guard !scored.isEmpty else { return nil }

    let host = baseURL.host?.lowercased() ?? ""

    if host.contains("amazon.") || host.contains("media-amazon.") {
        if let productImage = scored
            .filter({ isAmazonProductImageURL($0.url) })
            .max(by: { $0.score < $1.score }) {
            return productImage.url
        }

        if let nonLogo = scored
            .filter({ !looksLikeAmazonLogoURL($0.url) })
            .max(by: { $0.score < $1.score }) {
            return nonLogo.url
        }
    }

    return scored.max(by: { $0.score < $1.score })?.url
}

private func extractProductName(from html: String) -> String? {
    let metaCandidates: [(String, String)] = [
        ("property", "product:title"),
        ("property", "og:title"),
        ("name", "twitter:title"),
        ("itemprop", "name"),
        ("name", "title")
    ]

    if let meta = firstMetaContent(in: html, keys: metaCandidates) {
        return meta
    }

    let h1Pattern = #"<h1[^>]*>(.*?)</h1>"#
    if let regex = try? NSRegularExpression(pattern: h1Pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
       let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
       let range = Range(match.range(at: 1), in: html) {
        let raw = String(html[range]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }

    return nil
}

private func firstMetaContent(in html: String, keys: [(String, String)]) -> String? {
    let range = NSRange(location: 0, length: html.utf16.count)
    for (attribute, value) in keys {
        let pattern = "<meta[^>]*\(attribute)=[\\\"']\(value)[\\\"'][^>]*content=[\\\"'](.*?)[\\\"'][^>]*>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, options: [], range: range),
           let contentRange = Range(match.range(at: 1), in: html) {
            let content = String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { return content }
        }
    }
    return nil
}

private struct AvailabilityInfo {
    let text: String?
    let inStock: Bool?
}

private func extractAvailabilityInfo(from html: String) -> AvailabilityInfo {
    let range = NSRange(location: 0, length: html.utf16.count)
    let availabilityPatterns = [
        #"<meta[^>]*(?:itemprop|property|name)=[\"']availability[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#,
        #"<link[^>]*(?:itemprop|property|name)=[\"']availability[\"'][^>]*href=[\"'](.*?)[\"'][^>]*>"#
    ]

    for pattern in availabilityPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: html, options: [], range: range),
           let contentRange = Range(match.range(at: 1), in: html) {
            let raw = String(html[contentRange])
            let normalized = normalizeAvailability(raw)
            if normalized.text != nil || normalized.inStock != nil {
                return normalized
            }
        }
    }

    let snippet = html.prefix(4000).lowercased()
    if snippet.contains("sold out") || snippet.contains("out of stock") {
        return AvailabilityInfo(text: "Out of stock", inStock: false)
    }
    if snippet.contains("pre-order") || snippet.contains("preorder") {
        return AvailabilityInfo(text: "Pre-order", inStock: nil)
    }
    if snippet.contains("in stock") || snippet.contains("available now") {
        return AvailabilityInfo(text: "In stock", inStock: true)
    }

    return AvailabilityInfo(text: nil, inStock: nil)
}

private func normalizeAvailability(_ raw: String) -> AvailabilityInfo {
    let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if cleaned.isEmpty { return AvailabilityInfo(text: nil, inStock: nil) }

    let tokens = ["instock", "http://schema.org/instock", "https://schema.org/instock"]
    if tokens.contains(where: { cleaned.contains($0) }) {
        return AvailabilityInfo(text: "In stock", inStock: true)
    }

    let outTokens = ["outofstock", "out_of_stock", "http://schema.org/outofstock", "https://schema.org/outofstock"]
    if outTokens.contains(where: { cleaned.contains($0) }) {
        return AvailabilityInfo(text: "Out of stock", inStock: false)
    }

    if cleaned.contains("preorder") || cleaned.contains("pre-order") {
        return AvailabilityInfo(text: "Pre-order", inStock: nil)
    }

    if cleaned.contains("limited") {
        return AvailabilityInfo(text: raw.trimmingCharacters(in: .whitespacesAndNewlines), inStock: nil)
    }

    return AvailabilityInfo(text: raw.trimmingCharacters(in: .whitespacesAndNewlines), inStock: nil)
}

private func isProductLike(html: String, baseURL: URL, hasPrice: Bool, availability: String?) -> Bool {
    if hasPrice { return true }
    if availability != nil { return true }

    let lower = html.lowercased()
    if lower.contains("og:type\" content=\"product") { return true }
    if lower.contains("og:type\" content=\"Product".lowercased()) { return true }
    if lower.contains("schema.org/product") { return true }
    if lower.contains("product:price") { return true }
    if let host = baseURL.host?.lowercased() {
        if host.contains("shop") || host.contains("store") || host.contains("product") { return true }
    }
    return false
}

func extractHTMLPrice(from html: String) -> (String?, String?) {
    let range = NSRange(location: 0, length: html.utf16.count)
    let priceMetaPattern = #"<meta[^>]*property=[\"'](?:product:price:amount|og:price:amount)[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
    let currencyMetaPattern = #"<meta[^>]*property=[\"'](?:product:price:currency|og:price:currency)[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
    let priceMetaRegex = try? NSRegularExpression(pattern: priceMetaPattern, options: [.caseInsensitive])
    let currencyMetaRegex = try? NSRegularExpression(pattern: currencyMetaPattern, options: [.caseInsensitive])
    var price: String? = nil
    var currency: String? = nil
    if let match = priceMetaRegex?.firstMatch(in: html, options: [], range: range),
       let r = Range(match.range(at: 1), in: html) {
        price = String(html[r])
    }
    if let match = currencyMetaRegex?.firstMatch(in: html, options: [], range: range),
       let r = Range(match.range(at: 1), in: html) {
        currency = String(html[r])
    }

    if price == nil {
        let textOnly = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let pricePattern = #"([\$€£¥₹])\s*(\d+[\d.,]*)"#
        if let regex = try? NSRegularExpression(pattern: pricePattern, options: []),
           let match = regex.firstMatch(in: textOnly, options: [], range: NSRange(location: 0, length: textOnly.utf16.count)),
           let rSymbol = Range(match.range(at: 1), in: textOnly),
           let rAmount = Range(match.range(at: 2), in: textOnly) {
            currency = currency ?? String(textOnly[rSymbol])
            price = String(textOnly[rAmount])
        }
    }

    let sanitized = sanitizedPrice(price)
    if sanitized == nil, let original = price {
        print("⚠️ WebFetcher: Discarding placeholder price value '\(original)'")
    }
    return (sanitized, currency)
}

private func sanitizedPrice(_ rawPrice: String?) -> String? {
    guard let rawPrice = rawPrice?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPrice.isEmpty else {
        return nil
    }

    // Keep original formatting if numeric value looks reasonable.
    let numericValue = numericPriceValue(from: rawPrice)
    if let value = numericValue, value <= 1.0 {
        return nil
    }

    return rawPrice
}

private func numericPriceValue(from rawPrice: String) -> Double? {
    var filtered = rawPrice
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\n", with: "")

    filtered.removeAll { $0.isLetter }

    var numeric = filtered
    numeric.removeAll { !($0.isNumber || $0 == "." || $0 == ",") }

    if numeric.contains(",") && numeric.contains(".") {
        numeric = numeric.replacingOccurrences(of: ",", with: "")
    } else if numeric.contains(",") {
        numeric = numeric.replacingOccurrences(of: ",", with: ".")
    }

    return Double(numeric)
}

extension String {
    var htmlDecoded: String {
        var result = self

        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " "
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);", options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            var updated = result
            for match in matches.reversed() {
                guard match.numberOfRanges > 1 else { continue }
                let entity = nsString.substring(with: match.range(at: 1))
                let replacement: String?
                if entity.lowercased().hasPrefix("x") {
                    let hex = String(entity.dropFirst())
                    if let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) {
                        replacement = String(Character(scalar))
                    } else {
                        replacement = nil
                    }
                } else {
                    if let value = UInt32(entity, radix: 10), let scalar = UnicodeScalar(value) {
                        replacement = String(Character(scalar))
                    } else {
                        replacement = nil
                    }
                }

                if let replacement {
                    let range = Range(match.range, in: updated)!
                    updated.replaceSubrange(range, with: replacement)
                }
            }
            result = updated
        }

        return result
    }
}

private func isAmazonProductImageURL(_ urlString: String) -> Bool {
    let lower = urlString.lowercased()
    guard lower.contains("amazon.") || lower.contains("media-amazon.") else { return false }

    if looksLikeAmazonLogoURL(lower) { return false }

    let pathSignals = ["/images/i/", "/images/g/", "/images/p/", "/images/s/"]
    if pathSignals.contains(where: { lower.contains($0) }) { return true }
    if lower.contains("_ac_") || lower.contains("._ac_") { return true }

    return false
}

private func looksLikeAmazonLogoURL(_ urlString: String) -> Bool {
    let lower = urlString.lowercased()
    let stopWords = ["logo", "sprite", "nav", "favicon", "amazonfresh"]
    return stopWords.contains(where: { lower.contains($0) })
}

private func extractOpenGraphImage(from html: String, baseURL: URL) -> String? {
    let ogPattern = #"<meta[^>]*property=[\"']og:image[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
    let regex = try? NSRegularExpression(pattern: ogPattern, options: [.caseInsensitive])
    let range = NSRange(location: 0, length: html.utf16.count)
    if let match = regex?.firstMatch(in: html, options: [], range: range),
       let urlRange = Range(match.range(at: 1), in: html) {
        let imageURL = String(html[urlRange])
        return normalizeImageURL(imageURL, baseURL: baseURL)
    }
    return nil
}

private func extractTwitterCardImage(from html: String, baseURL: URL) -> String? {
    let twitterPattern = #"<meta[^>]*name=[\"']twitter:image[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
    let regex = try? NSRegularExpression(pattern: twitterPattern, options: [.caseInsensitive])
    let range = NSRange(location: 0, length: html.utf16.count)
    if let match = regex?.firstMatch(in: html, options: [], range: range),
       let urlRange = Range(match.range(at: 1), in: html) {
        let imageURL = String(html[urlRange])
        return normalizeImageURL(imageURL, baseURL: baseURL)
    }
    return nil
}

private func extractLargeImage(from html: String, baseURL: URL) -> String? {
    let imgWithSizePattern = #"<img[^>]*(?:width=[\"']?(\d+)[\"']?[^>]*height=[\"']?(\d+)[\"']?|height=[\"']?(\d+)[\"']?[^>]*width=[\"']?(\d+)[\"']?)[^>]*src=[\"'](.*?)[\"'][^>]*>"#
    let regex = try? NSRegularExpression(pattern: imgWithSizePattern, options: [.caseInsensitive])
    let range = NSRange(location: 0, length: html.utf16.count)
    var bestImage: (url: String, size: Int)? = nil
    regex?.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
        guard let match = match else { return }
        var width: Int = 0
        var height: Int = 0
        var imageURL: String = ""
        if match.range(at: 1).location != NSNotFound,
           let widthRange = Range(match.range(at: 1), in: html),
           let heightRange = Range(match.range(at: 2), in: html),
           let urlRange = Range(match.range(at: 5), in: html) {
            width = Int(String(html[widthRange])) ?? 0
            height = Int(String(html[heightRange])) ?? 0
            imageURL = String(html[urlRange])
        } else if match.range(at: 3).location != NSNotFound,
                  let heightRange = Range(match.range(at: 3), in: html),
                  let widthRange = Range(match.range(at: 4), in: html),
                  let urlRange = Range(match.range(at: 5), in: html) {
            height = Int(String(html[heightRange])) ?? 0
            width = Int(String(html[widthRange])) ?? 0
            imageURL = String(html[urlRange])
        }
        let area = width * height
        if area >= 40000 && (bestImage == nil || area > bestImage!.size) {
            if let normalizedURL = normalizeImageURL(imageURL, baseURL: baseURL) {
                bestImage = (normalizedURL, area)
            }
        }
    }
    return bestImage?.url
}

private func extractFirstImageURL(from html: String, baseURL: URL) -> String? {
    let imgPattern = #"<img[^>]*src=[\"'](.*?)[\"'][^>]*>"#
    let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive])
    let range = NSRange(location: 0, length: html.utf16.count)
    let skipPatterns = ["icon", "avatar", "logo", "favicon", "thumb"]
    let matches = regex?.matches(in: html, options: [], range: range) ?? []
    for match in matches {
        if let urlRange = Range(match.range(at: 1), in: html) {
            let imageURL = String(html[urlRange])
            let lowercaseURL = imageURL.lowercased()
            let shouldSkip = skipPatterns.contains { pattern in lowercaseURL.contains(pattern) }
            if !shouldSkip { return normalizeImageURL(imageURL, baseURL: baseURL) }
        }
    }
    if let firstMatch = matches.first, let urlRange = Range(firstMatch.range(at: 1), in: html) {
        let imageURL = String(html[urlRange])
        return normalizeImageURL(imageURL, baseURL: baseURL)
    }
    return nil
}

func normalizeImageURL(_ imageURL: String, baseURL: URL) -> String? {
    let trimmedURL = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedURL.hasPrefix("//") {
        return (baseURL.scheme ?? "https") + ":" + trimmedURL
    } else if trimmedURL.hasPrefix("/") {
        return "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(trimmedURL)"
    } else if !trimmedURL.hasPrefix("http") {
        return "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")/\(trimmedURL)"
    }
    return trimmedURL.isEmpty ? nil : trimmedURL
}

func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
    normalizedTitle(lhs) == normalizedTitle(rhs)
}

private func normalizedTitle(_ value: String) -> String {
    var normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

// Format content for a note created from web metadata
func formatWebContent(title: String, url: URL, content: String, imageURL: String?) -> String {
    var sections: [String] = []

    let hostLabel = url.host ?? "Link"
    sections.append("**Source:** [\(hostLabel)](\(url.absoluteString))")

    if let imageURL, !imageURL.isEmpty {
        sections.append("![Preview Image](\(imageURL))")
    }

    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedContent.isEmpty {
        sections.append(trimmedContent)
    }

    return sections.joined(separator: "\n\n")
}

/// Returns the same URL but with https scheme if the input used http; otherwise returns the original.
func upgradedToHTTPS(_ url: URL) -> URL {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" else { return url }
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    comps?.scheme = "https"
    return comps?.url ?? url
}


private func extractYouTubeThumbnailURL(from baseURL: URL, html: String) -> String? {
    guard let host = baseURL.host?.lowercased(), host.contains("youtube.com") || host.contains("youtu.be") else { return nil }

    func videoID(from url: URL) -> String? {
        if let host = url.host?.lowercased(), host.contains("youtu.be") {
            let parts = url.path.split(separator: "/").map(String.init)
            return parts.first
        }
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty { return v }
            // Sometimes embedded URLs use /embed/<id>
            let parts = url.path.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(of: "embed"), parts.indices.contains(idx+1) { return parts[idx+1] }
        }
        return nil
    }

    var vid = videoID(from: baseURL)

    // Try meta og:url or og:video:url
    if vid == nil {
        let range = NSRange(location: 0, length: html.utf16.count)
        let patterns = [
            #"<meta[^>]*property=[\"']og:url[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#,
            #"<meta[^>]*property=[\"']og:video:url[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = re.firstMatch(in: html, options: [], range: range),
               let r = Range(m.range(at: 1), in: html),
               let u = URL(string: String(html[r])) {
                vid = videoID(from: u)
                if vid != nil { break }
            }
        }
    }

    guard let id = vid else { return nil }
    // Use hqdefault for reliability; maxresdefault may 404 for many videos
    return "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
}

private func extractJSONLDImageURLs(from html: String) -> [String] {
    var results: [String] = []
    let pattern = #"<script[^>]*type=\"application/ld\+json\"[^>]*>(.*?)</script>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return results }
    let range = NSRange(location: 0, length: html.utf16.count)
    let matches = regex.matches(in: html, options: [], range: range)
    for m in matches {
        guard let r = Range(m.range(at: 1), in: html) else { continue }
        let jsonText = String(html[r])
        // Try to decode loosely
        if let data = jsonText.data(using: .utf8) {
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                func collect(from any: Any) {
                    if let s = any as? String { results.append(s) }
                    else if let arr = any as? [Any] { arr.forEach { collect(from: $0) } }
                    else if let dict = any as? [String: Any] {
                        if let s = dict["image"] { collect(from: s) }
                        if let s = dict["url"] as? String { results.append(s) }
                        if let s = dict["contentUrl"] as? String { results.append(s) }
                    }
                }
                collect(from: obj)
            } catch {
                continue
            }
        }
    }
    return results
}

private func extractMetaImageCandidates(from html: String) -> [(url: String, width: Int?, height: Int?)] {
    var out: [(String, Int?, Int?)] = []
    let range = NSRange(location: 0, length: html.utf16.count)

    let keys = [
        ("property", "og:image"),
        ("property", "og:image:url"),
        ("property", "og:image:secure_url"),
        ("name", "twitter:image"),
        ("name", "twitter:image:src")
    ]

    for (attr, val) in keys {
        let pattern = "<meta[^>]*\(attr)=[\\\"']\(val)[\\\"'][^>]*content=[\\\"'](.*?)[\\\"'][^>]*>"
        if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let matches = re.matches(in: html, options: [], range: range)
            for m in matches {
                if let r = Range(m.range(at: 1), in: html) {
                    out.append((String(html[r]), nil, nil))
                }
            }
        }
    }

    // Attach og:image width/height if present (use first values found)
    var widthVal: Int? = nil
    var heightVal: Int? = nil
    if let wRe = try? NSRegularExpression(pattern: #"<meta[^>]*property=[\"']og:image:width[\"'][^>]*content=[\"'](\d+)[\"'][^>]*>"#, options: [.caseInsensitive]),
       let m = wRe.firstMatch(in: html, options: [], range: range), let r = Range(m.range(at: 1), in: html) {
        widthVal = Int(String(html[r]))
    }
    if let hRe = try? NSRegularExpression(pattern: #"<meta[^>]*property=[\"']og:image:height[\"'][^>]*content=[\"'](\d+)[\"'][^>]*>"#, options: [.caseInsensitive]),
       let m = hRe.firstMatch(in: html, options: [], range: range), let r = Range(m.range(at: 1), in: html) {
        heightVal = Int(String(html[r]))
    }

    if widthVal != nil || heightVal != nil {
        out = out.map { ($0.0, widthVal, heightVal) }
    }

    return out
}

private func extractImgTagCandidates(from html: String) -> [(url: String, width: Int?)] {
    var out: [(String, Int?)] = []
    let range = NSRange(location: 0, length: html.utf16.count)

    // Extract srcset with widths, pick the largest for each tag
    let imgPattern = #"<img[^>]*>"#
    guard let imgRe = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) else { return out }
    let tags = imgRe.matches(in: html, options: [], range: range)

    for tag in tags {
        guard let tagRange = Range(tag.range(at: 0), in: html) else { continue }
        let tagHTML = String(html[tagRange])

        func firstAttr(_ name: String) -> String? {
            let p = "\\b\(name)\\s*=\\s*[\\\"'](.*?)[\\\"']"
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = re.firstMatch(in: tagHTML, options: [], range: NSRange(location: 0, length: tagHTML.utf16.count)),
               let r = Range(m.range(at: 1), in: tagHTML) {
                return String(tagHTML[r])
            }
            return nil
        }

        var bestURL: String? = nil
        var bestWidth: Int? = nil

        if let srcset = firstAttr("srcset") {
            // Parse entries like: url 320w, url2 640w, url3 1280w
            let parts = srcset.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for part in parts {
                let comps = part.split(separator: " ")
                if comps.count >= 2 {
                    let url = String(comps[0])
                    let wStr = comps[1].replacingOccurrences(of: "w", with: "")
                    let w = Int(wStr)
                    if bestWidth == nil || (w ?? 0) > (bestWidth ?? 0) {
                        bestWidth = w
                        bestURL = url
                    }
                }
            }
        }

        // Fallbacks: data-src, data-original, src
        if bestURL == nil {
            if let dataSrc = firstAttr("data-src") { bestURL = dataSrc }
            else if let dataOriginal = firstAttr("data-original") { bestURL = dataOriginal }
            else if let src = firstAttr("src") { bestURL = src }
        }

        if let u = bestURL {
            out.append((u, bestWidth))
        }
    }

    return out
}

private func scoreImageURL(_ url: String, width: Int?, height: Int?) -> Int {
    // Prefer explicit sizes when available
    if let w = width, let h = height { return w * h }
    if let w = width { return w * (w >= 800 ? 800 : 400) }

    // Heuristic: look for large numbers in URL path (e.g., 1200, 1080, 2048)
    let pattern = #"(\d{3,4})"#
    var bestNum = 0
    if let re = try? NSRegularExpression(pattern: pattern, options: []),
       let m = re.matches(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count)).last,
       let r = Range(m.range(at: 1), in: url) {
        bestNum = Int(String(url[r])) ?? 0
    }

    var score = bestNum

    // Bonus for common CDN hosts that often carry larger assets
    if url.contains("alicdn.com") || url.contains("cdn") || url.contains("cloudfront") || url.contains("akamai") {
        score += 200
    }

    return score
}
