import Foundation
import Darwin
import XCTest
@testable import MRWatcher

final class RuntimeSecurityTests: XCTestCase {
    func testSameOriginRedirectAllowsNormalizedHostAndDefaultPort() {
        XCTAssertTrue(
            SameOriginRedirectPolicy.permitsRedirect(
                from: URL(string: "https://GitLab.example.test/api/v4/merge_requests")!,
                to: URL(string: "https://gitlab.example.test.:443/api/v4/next")!
            )
        )
    }

    func testSameOriginRedirectRejectsChangedOriginComponent() {
        let original = URL(string: "https://gitlab.example.test/api/v4/merge_requests")!

        XCTAssertFalse(
            SameOriginRedirectPolicy.permitsRedirect(
                from: original,
                to: URL(string: "http://gitlab.example.test/api/v4/next")!
            )
        )
        XCTAssertFalse(
            SameOriginRedirectPolicy.permitsRedirect(
                from: original,
                to: URL(string: "https://other.example.test/api/v4/next")!
            )
        )
        XCTAssertFalse(
            SameOriginRedirectPolicy.permitsRedirect(
                from: original,
                to: URL(string: "https://gitlab.example.test:8443/api/v4/next")!
            )
        )
    }

    func testSecureDotEnvFileRequiresPrivateRegularFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let envURL = directory.appendingPathComponent(".env")
        let contents = "GITLAB_PAT=secret\n"
        try contents.write(to: envURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(envURL.path, 0o600), 0)
        XCTAssertEqual(SecureDotEnvFile.readContents(at: envURL), contents)

        XCTAssertEqual(chmod(envURL.path, 0o644), 0)
        XCTAssertNil(SecureDotEnvFile.readContents(at: envURL))

        try FileManager.default.removeItem(at: envURL)
        try FileManager.default.createDirectory(at: envURL, withIntermediateDirectories: false)
        XCTAssertNil(SecureDotEnvFile.readContents(at: envURL))
    }

    func testSecureDotEnvFileRejectsSymlink() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let targetURL = directory.appendingPathComponent("target.env")
        try "GITLAB_PAT=secret\n".write(to: targetURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(targetURL.path, 0o600), 0)

        let symlinkURL = directory.appendingPathComponent(".env")
        XCTAssertEqual(symlink(targetURL.path, symlinkURL.path), 0)
        XCTAssertNil(SecureDotEnvFile.readContents(at: symlinkURL))
    }

    func testSecureDotEnvFileAtomicReplacementIsOwnerOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let envURL = directory.appendingPathComponent(".env")
        let contents = "GITLAB_PAT=replaced-secret\n"
        try SecureDotEnvFile.replaceContents(contents, at: envURL)

        var fileInfo = stat()
        XCTAssertEqual(stat(envURL.path, &fileInfo), 0)
        XCTAssertEqual(fileInfo.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(fileInfo.st_mode & 0o077, 0)
        XCTAssertEqual(SecureDotEnvFile.readContents(at: envURL), contents)
    }
}
