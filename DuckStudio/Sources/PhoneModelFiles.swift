import Foundation
import StudioKit

/// The weights on disk: whether they are here, how much room they take, and
/// getting rid of them.
///
/// THE APP ENUMERATES, StudioKit SUMS. `PhoneModelInstall.totalBytes` does the
/// arithmetic, because `check_no_studio_math.sh` says the app draws and does not
/// compute — and because the number a person is shown before deleting three
/// gigabytes should be one a test can hold.
///
/// AND IT IS ALWAYS MEASURED, NEVER REMEMBERED. Nothing persists "downloaded:
/// true": a partial fetch, a reinstall, or iOS reclaiming a cache all make a
/// stored flag lie, and the truth is one directory listing away.
enum PhoneModelFiles {

    /// Where the hub client keeps its snapshots.
    ///
    /// CACHES, WHICH IOS MAY RECLAIM. `#hubDownloader()` puts weights under
    /// `Library/Caches/huggingface/hub`, and the system is entitled to delete
    /// anything there when the disk fills. That is a real property of this
    /// feature and the screen says so rather than promising the model stays.
    static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/hub", isDirectory: true)
    }

    static func directory(for repository: String) -> URL? {
        root?.appendingPathComponent(PhoneModelInstall.cacheSubpath(for: repository),
                                     isDirectory: true)
    }

    /// Bytes actually on disk for this repository, or nil when it is not here.
    static func bytesOnDisk(_ repository: String) -> Int? {
        guard let folder = directory(for: repository),
              FileManager.default.fileExists(atPath: folder.path),
              let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]) else { return nil }

        var sizes: [Int] = []
        for case let url as URL in walker {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                sizes.append(size)
            }
        }
        return PhoneModelInstall.totalBytes(sizes)
    }

    /// What is in the snapshot, for `PhoneModelInstall.state` to judge.
    ///
    /// THE APP ENUMERATES AND STUDIOKIT DECIDES. Returning paths and letting the
    /// kit rule on completeness is what makes "partly downloaded" testable on a
    /// machine with no phone attached.
    static func contents(_ repository: String) -> (paths: [String], index: Data?, bytes: Int) {
        guard let folder = directory(for: repository),
              let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]) else { return ([], nil, 0) }

        var paths: [String] = []
        var sizes: [Int] = []
        var index: Data?
        for case let url as URL in walker {
            // A snapshot is symlinks into blobs/; counting both sides doubles
            // the total and lists every file twice.
            let resolved = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?
                .isSymbolicLink ?? false
            if resolved { continue }
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                sizes.append(size)
            }
            paths.append(url.lastPathComponent)
            if url.lastPathComponent == "model.safetensors.index.json" {
                index = try? Data(contentsOf: url)
            }
        }
        return (paths, index, PhoneModelInstall.totalBytes(sizes))
    }

    /// How much of this model is actually here.
    static func state(_ repository: String) -> PhoneModelInstall.InstallState {
        let found = contents(repository)
        return PhoneModelInstall.state(paths: found.paths, indexJSON: found.index,
                                       bytes: found.bytes)
    }

    @discardableResult
    static func delete(_ repository: String) -> Bool {
        guard let directory = directory(for: repository) else { return false }
        return (try? FileManager.default.removeItem(at: directory)) != nil
    }
}
