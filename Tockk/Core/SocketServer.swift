import Foundation
import Darwin

final class SocketServer {
    private let path: String
    private let stateLock = NSLock()
    private var _running = false
    private var _listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "com.somee4.tockk.socket.accept")

    var onEvent: ((Event) -> Void)?

    init(path: String) { self.path = path }

    private func snapshot() -> (running: Bool, fd: Int32) {
        stateLock.lock(); defer { stateLock.unlock() }
        return (_running, _listenFD)
    }

    private func setRunning(_ value: Bool, fd: Int32) {
        stateLock.lock(); defer { stateLock.unlock() }
        _running = value
        _listenFD = fd
    }

    func start() throws {
        // Refuse to steal the socket path from a live listener. When a second
        // Tockk process unconditionally unlinks+rebinds, the original process's
        // fd becomes an orphan (lives in the kernel, no filesystem handle),
        // and if the second process later dies it leaves the socket file
        // pointing at a dead socket — clients then get ECONNREFUSED and the
        // CLI / in-app Trigger both silently break. Probing the existing path
        // with a non-blocking connect() tells us if anyone is still listening.
        if Self.isPathLive(path) {
            throw POSIXError(.EADDRINUSE)
        }
        try? FileManager.default.removeItem(atPath: path)
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd); throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                _ = pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dst, src.baseAddress, src.count)
                }
            }
        }

        let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addrSize) }
        }
        guard bindResult == 0 else {
            close(fd); throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
        }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else {
            close(fd); throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        setRunning(true, fd: fd)
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        stateLock.lock()
        let fd = _listenFD
        _running = false
        _listenFD = -1
        stateLock.unlock()
        if fd >= 0 { close(fd) }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Returns `true` if `path` is bound to a socket that currently accepts
    /// connections. Stale socket files (process exited without unlinking)
    /// fail with ECONNREFUSED and return `false`.
    private static func isPathLive(_ path: String) -> Bool {
        var info = Darwin.stat()
        guard Darwin.lstat(path, &info) == 0 else { return false }
        guard (mode_t(info.st_mode) & S_IFMT) == S_IFSOCK else { return false }

        let probeFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probeFD >= 0 else { return false }
        defer { close(probeFD) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                _ = pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dst, src.baseAddress, src.count)
                }
            }
        }
        let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probeFD, $0, addrSize) }
        }
        return result == 0
    }

    private func acceptLoop() {
        while true {
            let (running, fd) = snapshot()
            guard running, fd >= 0 else { return }
            let client = accept(fd, nil, nil)
            if client < 0 {
                let (stillRunning, _) = snapshot()
                if !stillRunning { return }
                continue
            }
            let handlerQueue = DispatchQueue(label: "com.somee4.tockk.socket.client.\(client)")
            handlerQueue.async { [weak self] in self?.handleClient(fd: client) }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while snapshot().running {
            let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
                read(fd, ptr.baseAddress, ptr.count)
            }
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            while let idx = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<idx)
                buffer.removeSubrange(buffer.startIndex...idx)
                if line.isEmpty { continue }
                do {
                    let event = try JSONDecoder.tockkDecoder.decode(Event.self, from: line)
                    DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
                } catch {
                    FileHandle.standardError.write(
                        Data("tockk: failed to decode event: \(error)\n".utf8)
                    )
                }
            }
        }
    }
}
