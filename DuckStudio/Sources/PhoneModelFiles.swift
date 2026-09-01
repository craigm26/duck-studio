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

        // THE NAMES AND THE BYTES ARE IN DIFFERENT PLACES, and conflating them
        // is what made a fully downloaded model read as partial forever.
        //
        // A Hugging Face snapshot directory holds SYMLINKS — `config.json`,
        // `tokenizer.json`, `model.safetensors` — pointing into `blobs/`, where
        // the data sits under opaque sha names. Skipping symlinks to avoid
        // double-counting bytes therefore skipped every file with a real name,
        // so `state` never found a config or a tokenizer and answered `.partial`
        // with 2.3 GB on the disk and a Resume button that could not finish.
        //
        // So: names come from the links, bytes come from the blobs.
        var paths: [String] = []
        var sizes: [Int] = []
        var index: Data?
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            let isLink = values?.isSymbolicLink ?? false

            // Every name, from wherever it appears. A blob's sha is not a name
            // anything looks for, so including it costs nothing.
            paths.append(url.lastPathComponent)

            // Bytes from real files only — counting a link and its target
            // doubles the total.
            if !isLink, let size = values?.fileSize { sizes.append(size) }

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
