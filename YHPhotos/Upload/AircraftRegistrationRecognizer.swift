import ImageIO
import UIKit
import Vision

/// Uses Apple's on-device text recognition and returns only strings that look
/// like civil aircraft registrations. No recognized text leaves the device.
enum AircraftRegistrationRecognizer {
    private struct Candidate {
        let value: String
        let confidence: Float
        let order: Int
    }

    private static let expression: NSRegularExpression = {
        let pattern = #"(?:B-[A-Z0-9]{3,5}|N[0-9]{1,5}[A-Z]{0,2}|JA(?:[0-9]{4}|[0-9]{2}[A-Z]{2})|HL[0-9]{4}|RA-[0-9]{5}|RP-C[0-9]{3,5}|C-[FGI][A-Z]{3}|(?:PR|PT|PP|PS|PU)-[A-Z]{3}|(?:G|D|F|I)-[A-Z]{4}|(?:EC|EI|PH|OO|OE|HB|SE|LN|OY|OH|CS|SP|OK|HA|OM|YU|9H|9V|A6|A7|A9C|VT|PK|HS|TC|SX|ZS|VH|ZK|ZL|CC|LV|XA|XB|XC)-[A-Z0-9]{3,5})"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func recognize(in data: Data) async throws -> String? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let candidates: [Candidate] = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.006

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])

            var matches: [Candidate] = []
            for (order, observation) in (request.results ?? []).enumerated() {
                for recognized in observation.topCandidates(3) {
                    let normalized = normalize(recognized.string)
                    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
                    expression.enumerateMatches(in: normalized, options: [], range: range) { match, _, _ in
                        guard let match, let swiftRange = Range(match.range, in: normalized) else { return }
                        matches.append(Candidate(
                            value: String(normalized[swiftRange]).uppercased(),
                            confidence: recognized.confidence,
                            order: order
                        ))
                    }
                }
            }
            return matches
        }.value

        return candidates
            .reduce(into: [String: Candidate]()) { best, candidate in
                if let existing = best[candidate.value], existing.confidence >= candidate.confidence { return }
                best[candidate.value] = candidate
            }
            .values
            .sorted {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.order < $1.order
            }
            .first?
            .value
    }

    private static func normalize(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
