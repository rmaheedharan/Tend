// The only TendEval file with a write API (AC-M2-28 "It writes nothing except the results file"; AC-M2-09 Rule 6). It
// writes one results file, format v1, as canonical JSON (`EvalResultsFileV1.canonicalJSON`), to the harness's
// Documents directory, which file sharing (Debug only) shows in the Files app and Finder. The file type has no field
// for audio, a request or response body, a header value or a key. Nothing is uploaded.

import Foundation
import TendIngestion

enum EvalResultsWriter {
    enum WriteError: Error {
        case notEncodable
        case notWritten
    }

    /// Writes `file` as `name` in Documents and returns the bytes written (for the on-screen SHA-256).
    @discardableResult
    static func write(_ file: EvalResultsFileV1, name: String) throws -> Data {
        let data: Data
        do {
            data = try CanonicalJSONWriter.data(file.canonicalJSON)
        } catch {
            throw WriteError.notEncodable
        }
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            try data.write(to: documents.appendingPathComponent(name, isDirectory: false),
                           options: [.atomic, .completeFileProtection])
        } catch {
            throw WriteError.notWritten
        }
        return data
    }
}
