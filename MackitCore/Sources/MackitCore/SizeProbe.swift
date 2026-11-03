import Darwin
import Foundation

public enum SizeProbe {
    /// Bytes freed by deleting this file: the APFS private size, which excludes blocks shared
    /// with clones. Falls back to the allocated size. Nil when the file cannot be read.
    public static func reclaimableBytes(_ url: URL) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(0x8000_0000)  // ATTR_CMN_RETURNED_ATTRS
        request.forkattr = attrgroup_t(0x0000_0008)  // ATTR_CMNEXT_PRIVATESIZE
        var buffer = [UInt8](repeating: 0, count: 64)
        let options = UInt32(0x20 | 0x1)  // FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW
        let rc = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return getattrlist(path, &request, &buffer, buffer.count, options)
        }
        if rc == 0 {
            // Layout: u_int32 length, attribute_set_t (5 x u_int32), then off_t private size.
            let returned = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 20, as: UInt32.self) }
            if returned & 0x8 != 0 {
                return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: Int64.self) }
            }
        }
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
            let size = values.totalFileAllocatedSize
        else { return nil }
        return Int64(size)
    }
}
