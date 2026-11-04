import Darwin
import Foundation

/// Fatal-signal capture. Installs a sigaction handler (with its own signal stack) for the
/// signals a trapped Swift process actually dies from, writes the ring tail plus a backtrace
/// to a pre-opened crash file using async-signal-safe calls only, then restores the previous
/// handler and re-raises so Apple's ReportCrash still fires.
public enum CrashHandler {
    public static let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]

    /// Fixed-format crash record. No allocation: writes bytes into the caller's buffer only.
    /// Returns the number of bytes written.
    public static func crashRecord(
        signal: Int32, code: Int32, address: UInt,
        ringTail: UnsafeRawPointer?, tailLen: Int,
        into out: UnsafeMutableRawPointer, capacity: Int
    ) -> Int {
        var offset = 0
        func emit(_ s: UnsafePointer<UInt8>) {
            var i = 0
            while s[i] != 0 && offset < capacity {
                (out + offset).storeBytes(of: s[i], as: UInt8.self)
                i += 1
                offset += 1
            }
        }
        // Digit count via division (max 20 digits for UInt); divisor peaks at 10^19, no overflow.
        func emitNumber(_ value: UInt) {
            var len = 1
            var scaled = value / 10
            while scaled > 0 {
                len += 1
                scaled /= 10
            }
            var divisor: UInt = 1
            for _ in 1..<len { divisor *= 10 }
            while divisor > 0 {
                guard offset < capacity else { break }
                (out + offset).storeBytes(of: UInt8(0x30 + (value / divisor) % 10), as: UInt8.self)
                offset += 1
                divisor /= 10
            }
        }
        func emitHex(_ value: UInt) {
            emit("0x")
            var shift = UInt.bitWidth - 4
            var started = false
            while shift >= 0 {
                let nibble = Int((value >> UInt(shift)) & 0xF)
                if nibble != 0 || started || shift == 0 {
                    started = true
                    if offset < capacity {
                        let digit = UInt8(nibble < 10 ? 0x30 + nibble : 0x61 + nibble - 10)
                        (out + offset).storeBytes(of: digit, as: UInt8.self)
                        offset += 1
                    }
                }
                shift -= 4
            }
        }

        emit("MACKIT CRASH\nsignal: ")
        switch signal {
        case SIGABRT: emit("SIGABRT")
        case SIGSEGV: emit("SIGSEGV")
        case SIGBUS: emit("SIGBUS")
        case SIGILL: emit("SIGILL")
        case SIGFPE: emit("SIGFPE")
        case SIGTRAP: emit("SIGTRAP")
        default: emit("SIG")
        }
        emit(" (")
        emitNumber(UInt(signal))
        emit(") code ")
        emitNumber(UInt(Int(code)))
        emit(" addr ")
        emitHex(address)
        emit("\n")
        if let active, let session = active.sessionID {
            emit("session: ")
            emit(session)
            emit("\n")
        }
        if let tail = ringTail, tailLen > 0 {
            emit("\n--- last events ---\n")
            var i = 0
            while i < tailLen && offset < capacity {
                (out + offset).storeBytes(of: tail.load(fromByteOffset: i, as: UInt8.self), as: UInt8.self)
                i += 1
                offset += 1
            }
        }
        return offset
    }

    /// Per-process install state. Written once at launch (before any crash can matter) and
    /// read from the signal handler; safe because the handler runs on the same thread of
    /// execution the crash interrupted, not concurrently with install.
    private final class Active: @unchecked Sendable {
        let fd: Int32
        let buffer: UnsafeMutableRawPointer
        let bufferSize = 32_768
        let sessionID: [UInt8]?
        var previous: [Int32: sigaction] = [:]
        var oldStack: stack_t = stack_t()
        let stack: UnsafeMutableRawPointer
        let recorder: FlightRecorder?

        init(fd: Int32, recorder: FlightRecorder?, sessionID: [UInt8]?) {
            self.fd = fd
            self.recorder = recorder
            self.sessionID = sessionID
            buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
            stack = UnsafeMutableRawPointer.allocate(byteCount: Int(SIGSTKSZ) * 8, alignment: 1)
        }
    }

    private nonisolated(unsafe) static var active: Active?

    static var isInstalled: Bool { active != nil }

    /// Installs the handler for all fatal signals. Pre-opens `crash.txt` for append (the fd
    /// the handler will write to), allocates one signal stack, and returns the previous
    /// handlers so tests (and a hypothetical re-install) can inspect them.
    @discardableResult
    public static func install(directory: URL, recorder: FlightRecorder?) -> [Int32: sigaction] {
        let crashPath = directory.appendingPathComponent("crash.txt").path
        let fd = open(crashPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return [:] }
        let session = recorder.map { Array($0.sessionID.utf8) }
        let oldActive = active
        let state = Active(fd: fd, recorder: recorder, sessionID: session)
        active = state

        var stack = stack_t(ss_sp: state.stack, ss_size: Int(SIGSTKSZ) * 8, ss_flags: 0)
        sigaltstack(&stack, &state.oldStack)

        // Never record our own handler as the previous one — a later restore would loop
        // handle -> raise -> handle forever. Any other current handler is kept as previous.
        var previous = oldActive?.previous ?? [:]
        for sig in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_sigaction = handler
            action.sa_flags = Int32(SA_SIGINFO | SA_ONSTACK)
            var current = sigaction()
            sigaction(sig, &action, &current)
            if let f = current.__sigaction_u.__sa_sigaction,
                Int(bitPattern: unsafeBitCast(f, to: UnsafeRawPointer.self)) != handlerAddress
            {
                previous[sig] = current
            }
        }
        state.previous = previous
        return previous
    }

    /// C function pointer for sigaction; must not capture context, so it goes through the
    /// global `active` state.
    private static let handler:
        @convention(c) (Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void = { sig, info, _ in
            handle(sig, info)
        }

    private static let handlerAddress: Int = {
        Int(bitPattern: unsafeBitCast(handler, to: UnsafeRawPointer.self))
    }()

    private nonisolated(unsafe) static var inHandler = false

    /// The handler body: async-signal-safe calls only — write(2), memcpy via the pure record,
    /// backtrace_symbols_fd, sigaction, raise. No malloc beyond what libunwind already holds.
    private static func handle(_ sig: Int32, _ info: UnsafeMutablePointer<siginfo_t>?) {
        guard let state = active else { return }
        if inHandler {
            // A second fault while handling: get out of the way with the default action.
            var dfl = sigaction()
            sigemptyset(&dfl.sa_mask)
            dfl.__sigaction_u.__sa_handler = SIG_DFL
            sigaction(sig, &dfl, nil)
            raise(sig)
            return
        }
        inHandler = true
        let code = info?.pointee.si_code ?? 0
        let address = UInt(bitPattern: info?.pointee.si_addr)
        // Stage the ring tail in the second half of the buffer (memcpy, no allocation),
        // then render the record in the first half around it.
        var tailLen = 0
        if let recorder = state.recorder {
            tailLen = recorder.tail(into: state.buffer + 16_384, capacity: state.bufferSize - 16_384)
        }
        let n = crashRecord(
            signal: sig, code: Int32(code), address: address,
            ringTail: tailLen > 0 ? state.buffer + 16_384 : nil, tailLen: tailLen,
            into: state.buffer, capacity: state.bufferSize)
        if n > 0 { _ = write(state.fd, state.buffer, n) }
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
        let depth = Int(backtrace(&frames, Int32(frames.count)))
        backtrace_symbols_fd(&frames, Int32(depth), state.fd)
        // Restore the previous handler and re-raise so ReportCrash still produces its report.
        if let old = state.previous[sig] {
            var restored = old
            sigaction(sig, &restored, nil)
        }
        raise(sig)
    }
}
