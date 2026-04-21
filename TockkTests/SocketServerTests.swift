import XCTest
@testable import Tockk

final class SocketServerTests: XCTestCase {

    private func tempSocketPath() -> String {
        NSTemporaryDirectory() + "tockk-test-\(UUID().uuidString).sock"
    }

    func testServerReceivesAndDecodesSingleJSONLine() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path)
        let exp = expectation(description: "received")
        server.onEvent = { event in
            XCTAssertEqual(event.title, "hello")
            XCTAssertEqual(event.project, "demo")
            exp.fulfill()
        }
        try server.start()
        defer { server.stop() }

        sendLine(#"{"agent":"t","project":"demo","status":"success","title":"hello"}"#, to: path)
        wait(for: [exp], timeout: 2.0)
    }

    func testServerHandlesMultipleLinesInOneConnection() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path)
        let exp = expectation(description: "both")
        exp.expectedFulfillmentCount = 2
        server.onEvent = { _ in exp.fulfill() }
        try server.start()
        defer { server.stop() }

        let payload = [
            #"{"agent":"t","project":"p","status":"success","title":"a"}"#,
            #"{"agent":"t","project":"p","status":"success","title":"b"}"#
        ].joined(separator: "\n") + "\n"
        sendRaw(payload, to: path)
        wait(for: [exp], timeout: 2.0)
    }

    func testServerIgnoresMalformedJSONAndContinues() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path)
        let exp = expectation(description: "valid after garbage")
        server.onEvent = { event in
            XCTAssertEqual(event.title, "ok")
            exp.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let payload = "this is not json\n"
            + #"{"agent":"t","project":"p","status":"success","title":"ok"}"#
            + "\n"
        sendRaw(payload, to: path)
        wait(for: [exp], timeout: 2.0)
    }

    func testSocketFileHasOwnerOnlyPermissions() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path)
        try server.start()
        defer { server.stop() }
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    // MARK: - Helpers

    private func sendLine(_ line: String, to socketPath: String) {
        sendRaw(line + "\n", to: socketPath)
    }

    private func sendRaw(_ payload: String, to socketPath: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThan(fd, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                _ = pathBytes.withUnsafeBufferPointer { src in memcpy(dst, src.baseAddress, src.count) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        XCTAssertEqual(r, 0, "connect failed errno=\(errno)")
        _ = payload.withCString { ptr in send(fd, ptr, strlen(ptr), 0) }
        close(fd)
    }
}
