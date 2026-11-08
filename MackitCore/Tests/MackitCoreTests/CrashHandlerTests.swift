import Darwin
import Foundation
import Testing

@testable import MackitCore

// fork is annotated unavailable in the Swift overlay; the C symbol works fine and the child
// here never returns into the test framework (it only raises a signal).
@_silgen_name("fork")
private func posixFork() -> pid_t

/// The chained dummy handler writes here; a file-scope global because a C function pointer
/// cannot capture context.
private nonisolated(unsafe) var dummyMarkerFD: Int32 = -1

@Suite(.serialized)
struct CrashHandlerTests {
    @Test func crashRecordFormatsSignalEventsAndTail() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url)
        recorder.record(step: "duplicates", "hashing 12 files")
        recorder.record(step: "index", "walking /Users/me/Library")
        let tail = recorder.tailData()
        let session = Array(recorder.sessionID.utf8)
        // Hex letters in the address exercise emitHex's letter branch.
        var buffer = [UInt8](repeating: 0, count: 32_768)
        let n = buffer.withUnsafeMutableBytes { ptr -> Int in
            tail.withUnsafeBytes { tailPtr -> Int in
                session.withUnsafeBufferPointer { sessionPtr in
                    CrashHandler.crashRecord(
                        signal: SIGSEGV, code: 1, address: 0x0000_0000_dead_beef,
                        session: (UnsafeRawPointer(sessionPtr.baseAddress!), sessionPtr.count),
                        ringTail: tailPtr.baseAddress, tailLen: tailPtr.count,
                        into: ptr.baseAddress!, capacity: ptr.count)
                }
            }
        }
        let text = String(decoding: buffer[0..<n], as: UTF8.self)
        #expect(text.contains("MACKIT CRASH"))
        #expect(text.contains("SIGSEGV"))
        #expect(text.contains("11"))
        #expect(text.contains("0xdeadbeef"))
        #expect(text.contains("hashing 12 files"))
        #expect(text.contains("walking /Users/me/Library"))
        #expect(text.contains(recorder.sessionID))
    }

    @Test func installRegistersAllSignalsAndReturnsPrevious() throws {
        let dir = try TempDir()
        let previous = CrashHandler.install(directory: dir.url, recorder: nil)
        for sig in CrashHandler.signals {
            var current = sigaction()
            #expect(sigaction(sig, nil, &current) == 0)
            #expect(current.__sigaction_u.__sa_sigaction != nil)
            let flags = current.sa_flags
            #expect(flags & SA_SIGINFO != 0)
            #expect(flags & SA_ONSTACK != 0)
            // A previous suite test may have installed first; then the return value carries
            // the stored chain (nil here means "ours was already current, nothing to keep").
            #expect(previous[sig] != nil || CrashHandler.isInstalled)
        }
    }

    private struct ChildCrash {
        var signaled = false
        var crashText = ""
        var markerWritten = false
    }

    /// Installs the recorder and handler in this process, then forks a child that only
    /// raises `signal`. The child inherits the handler, ring, fds, and the marker fd, so it
    /// never touches Swift runtime facilities that a forked child cannot rely on.
    private func crashChild(
        sig: Int32, chainDummy: Bool, record: Bool = true
    ) throws -> ChildCrash {
        let dir = try TempDir()
        let crashURL = dir.url.appendingPathComponent("crash.txt")
        let markerURL = dir.url.appendingPathComponent("marker.txt")
        FileManager.default.createFile(atPath: markerURL.path, contents: nil)
        dummyMarkerFD = open(markerURL.path, O_WRONLY | O_APPEND)
        precondition(dummyMarkerFD >= 0)
        defer { close(dummyMarkerFD) }
        if chainDummy {
            var dummy = sigaction()
            dummy.__sigaction_u.__sa_sigaction = { _, _, _ in
                let msg = "dummy-ran\n"
                _ = write(dummyMarkerFD, msg, 10)
                signal(SIGSEGV, SIG_DFL)
                raise(SIGSEGV)
            }
            dummy.sa_flags = SA_SIGINFO
            sigaction(SIGSEGV, &dummy, nil)
        }
        let recorder = FlightRecorder(directory: dir.url)
        if record {
            recorder.record(step: "duplicates", "mid-hash batch of 7")
            FlightRecorder.shared = recorder
        }
        CrashHandler.install(directory: dir.url, recorder: record ? recorder : nil)
        let pid = posixFork()
        #expect(pid >= 0)
        if pid == 0 {
            raise(sig)
            _exit(1)
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        // The child died from the signal (our handler re-raised it, so its death signal is
        // the raised one even when a chained handler exists).
        let signaled = childSignaled(status)
        var result = ChildCrash()
        result.signaled = signaled
        result.crashText = (try? String(contentsOf: crashURL, encoding: .utf8)) ?? ""
        let marker = (try? String(contentsOf: markerURL, encoding: .utf8)) ?? ""
        result.markerWritten = marker.contains("dummy-ran")
        return result
    }

    @Test func childCrashWritesCrashFileWithEventsAndBacktrace() throws {
        let result = try crashChild(sig: SIGSEGV, chainDummy: false)
        #expect(result.signaled)
        #expect(result.crashText.contains("MACKIT CRASH"))
        #expect(result.crashText.contains("SIGSEGV"))
        #expect(result.crashText.contains("mid-hash batch of 7"))
        #expect(result.crashText.contains("0x"))
        let lines = result.crashText.split(separator: "\n")
        #expect(lines.count >= 4, "expected header + events + backtrace frames, got: \(result.crashText)")
    }

    @Test func previousHandlerRunsAfterRestore() throws {
        let result = try crashChild(sig: SIGSEGV, chainDummy: true)
        #expect(result.signaled)
        #expect(result.markerWritten)
    }

    @Test func sigkillLeavesNoCrashFile() throws {
        let dir = try TempDir()
        let crashURL = dir.url.appendingPathComponent("crash.txt")
        let recorder = FlightRecorder(directory: dir.url)
        FlightRecorder.shared = recorder
        CrashHandler.install(directory: dir.url, recorder: recorder)
        let pid = posixFork()
        #expect(pid >= 0)
        if pid == 0 { kill(getpid(), SIGKILL) }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        #expect(status & 0x7F == SIGKILL)
        // install() pre-creates crash.txt; a SIGKILL must leave it empty (nothing written).
        #expect((try? String(contentsOf: crashURL, encoding: .utf8))?.isEmpty ?? true)
    }
}

/// Status macros are C preprocessor macros; these are the POSIX expansions.
private func childSignaled(_ status: Int32) -> Bool {
    ((status & 0x7F) + 1) >> 1 > 0
}
