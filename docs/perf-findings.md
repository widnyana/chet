# Performance findings

Status: review of the scan, duplicate, app, Homebrew, and disk map paths.
Date: 2026-11-09.
Machine: MacBook, 16 GB RAM, macOS 27.0.1, 8 cores. Chet scan limit: 1.5 GB peak RSS.

## The incident

A scan of `~/Development` (110 GB; the heap held 93,097 live `NSURL`s at the 6.7 GB
sample point) reached the duplicates step, grew to **51.36 GB physical footprint**,
and the process was killed. Around that 6.7 GB point `vmmap` reported 8.4 GB swapped
out for the process. The host showed 86.6M cumulative swapouts (`vm_stat`) by the end
of the tests.

The growth is not the index walk and not the UI. It is `DuplicateFinder` reading files
with `FileHandle` inside one long synchronous step.

Measured, with no slow consumer in the loop:

|Point|Footprint|Evidence|
|---|---|---|
|Index walk finished, 8 roots, 64,184 tree nodes|0.16 GB||
|Duplicates step starts|0.16 GB|`started duplicates`|
|85 s later, when the step returned|51.36 GB|probe checked its 3 GB guard on the next event, too late|
|First `chet-scan` run|50.98 GB peak memory footprint|`/usr/bin/time -l`, process terminated abnormally|

`sample` at about 10 GB put 790 of 991 samples in `DuplicateFinder.confirmed`, reading
through `NSFileHandle.read(upToCount:)`. `heap` at 6.7 GB reported only 522,729 live
malloc nodes (181,978 `CFString`, 93,097 `NSURL`), while `vmmap` reported 4.9 GB dirty
in the malloc small zone and only 49.6 MB in the malloc large zone. Live objects are
small and few. The memory is retained autoreleased Foundation traffic.

## Root cause, reproduced in isolation

`FileHandle.read(upToCount:)` bridges to autoreleased `NSData`. `ScanSession.run` calls
`finder.find` synchronously, with no suspension inside the step, so the concurrency
runtime's autorelease pool is not drained until the whole duplicate stage ends. Each
read buffer stays alive until then.

A 64 MiB file read 400 times (25 GiB of bytes) in a detached Swift task:

|Reader|Footprint|RSS|Wall|
|---|---|---|---|
|`FileHandle.read(upToCount: 1 << 20)`, no pool|**26.96 GB**|3.5 GB|8.3 s|
|Same, `autoreleasepool {}` per file|0.0897 GB|0.09 GB|3.8 s|
|POSIX `read` into one reused 1 MiB buffer|0.0042 GB|0.008 GB|1.7 s|

That ratio matches the 51 GB observed on the real tree, consistent with the duplicate
stage reading tens of GB and retaining memory in proportion to bytes read.

Relevant code:

- `ChetCore/Sources/ChetCore/DuplicateFinder.swift:119-134` `sameBytes`: two files,
  two `FileHandle`s, 1 MiB `Data` chunks.
- `DuplicateFinder.swift:149-158` `fullHash`: one `FileHandle`, 1 MiB `Data` chunks.
- `DuplicateFinder.swift:136-147` `edgeHash`: two small `Data` reads per file.
- `ChetCore/Sources/ChetCore/UncachedRead.swift`: every open goes through
  `FileHandle(forReadingFrom:)`.
- `ChetCore/Sources/ChetCore/ScanSession.swift:196-203`: the whole duplicates step is
  one synchronous call inside `run`.

Fix, in order of effect:

1. Replace `FileHandle` with POSIX `open`/`read` into one reusable
   `UnsafeMutableRawPointer` buffer per hashing pass. No per-chunk allocation, about
   5x faster in the micro test.
2. Put `autoreleasepool` around each file's hash or compare as the fallback. It alone
   takes the micro test from 26.96 GB to 0.09 GB.
3. Replace `hex` (`DuplicateFinder.swift:160-162`), which allocates 33 strings per
   digest (32 `String(format:)` plus the joined string), with a table-based encoder.

## Duplicate step algorithm cost

Besides the allocation bug, the step reads each candidate up to three times:

- `find(entries:)` (`DuplicateFinder.swift:45-68`) builds `bySize`, then for every
  size bucket with more than one member runs `edgeHash` on every member.
- Every edge-hash bucket with more than one member runs `fullHash` on every member,
  so the file is read end to end.
- Every full-hash bucket runs `confirmed` (`DuplicateFinder.swift:107-117`), which
  calls `sameBytes` against each confirmed subgroup representative, reading the file
  end to end again.
- `confirmed` is O(k x g) comparisons for a hash bucket of k entries and g confirmed
  byte groups, and each comparison is O(file size).

Cost for n candidates: O(total bytes hashed) I/O plus O(n) grouping, with up to three
full reads per matching candidate. Memory: O(bytes read) today because of the
autorelease issue, and O(n) for the bucket dictionaries otherwise.

Fix: read each file with one allocation-free pass, keep the digest, and confirm once
against the kept copy. Keep the edge hash as the cheap first filter, but make it
allocate nothing, and keep the table-based hex encoder. Cap the candidate count per
bucket and record how much was hashed so a giant bucket cannot run silently.

## Cost summary

|Path|Current|Target|
|---|---|---|
|Duplicates hashing|O(bytes) read, up to 3 passes per candidate|one pass per candidate|
|Duplicates memory|O(bytes read) retained until the step ends|O(1) per file, reused buffer|
|Scan events|unbounded queue, every rollup subtree retained|bounded queue, coalesced at 4 Hz|
|Rollup trees|O(N x depth) node builds, most discarded before use|O(nodes emitted)|
|Live tree|O(depth x siblings) copy per rollup, up to 3 trees alive|O(1) per update, 1 tree|
|Rule sizes|O(sum of candidate subtrees) re-walk|O(1) lookup from the index|
|Homebrew sizes|O(files) with unbounded concurrency and a URL array per folder|O(files), 4 workers|
|Photo pairs|O(n^2)|O(n log n) bucket, then pairs|
|Video pairs|O(v^2)|O(v log v) bucket, then pairs|
|Treemap row|O(n^2) worst case|O(n) with running row stats|
|Totals per render|O(items) with a fresh Set|O(1) stored values|
|Subprocess output|O(output)|O(cap)|

## Finding list

### P0, duplicates step memory growth

Covered above. `DuplicateFinder.sameBytes`, `fullHash`, `edgeHash`, and `hex`. Measured
51.36 GB footprint on `~/Development`; micro-reproduction 26.96 GB for 25.6 GiB read;
`autoreleasepool` 0.09 GB; POSIX buffer 0.004 GB. Owner: `ChetCore/DuplicateFinder.swift`.

### P1, unbounded scan event stream

`ChetCore/Sources/ChetCore/ScanSession.swift:110-118` uses
`AsyncStream(bufferingPolicy: .unbounded)`. The producer is the walk, with 8 worker
threads emitting rollups; the consumer is `ScanModel` on the main actor, and each
`.treeUpdate` also merges a tree and redraws the map. If the consumer falls behind,
every intermediate `FolderNode` subtree stays in the buffer. Nothing bounds that queue.

Measured index peak on `~/Development` was 0.24 GB, so it did not cause the incident,
but it is an unbounded queue by construction. Fix: coalesce in the producer. Keep one
pending rollup for the in-flight root and replace it as newer ones arrive, emit at
4 Hz, and keep `.rootMeasured` and the final `.folderTrees` lossless.

### P1, every finalized directory is materialized before the rollup filter

`ChetCore/Sources/ChetCore/FileIndex.swift:721-730` calls
`merge.snapshots(finalized, maxDepth:)` for every directory merge.
`TreeMerge.snapshots` (`FileIndex.swift:582-591`) then calls `folderNode`
(`FileIndex.swift:598-607`), which recursively builds the whole subtree to depth 6.
Only after that tree exists does the loop test `depth <= 2 || size >= 32 MB` and drop
most of it.

Cost: O(N x depth) `FolderNode` allocations over the walk, with every ancestor level
rebuilding the same descendants. Measured on the 110 GB tree: 2,565 rollup events and
266,618 rolled-up nodes (probe count), final tree 64,184 nodes. Fix: decide from the
`DirNode` id, depth, and size first, then build the tree only for the ids that pass.
Root snapshots should be built once, at the end.

### P1, live tree merge copies the path on every rollup

`Chet/ScanModel.swift:422-434` folds each rollup with `FolderNode.inserting` or
`merging` (`ChetCore/Sources/ChetCore/LargeFiles.swift:55-89`). Both return a new
value: every ancestor on the path copies its children array and re-sorts it. Per
rollup that is O(depth x siblings) allocations, and the resulting tree shares the
unmodified subtrees, but the arrays are rebuilt at every level.

At the same time the model keeps three representations of the same data:
`liveTree` (merged rollups), `partialTrees` (one full tree per measured root, appended
at `ScanModel.swift:480`), and `folderTrees` (final, `ScanModel.swift:472-477`). The
first two coexist for the whole index step; `.folderTrees` then replaces both. Fix:
one mutable tree owned by the model, updated in place, and a single final assignment.

### P1, rule scan re-walks what the index already walked

`ChetCore/Sources/ChetCore/RuleScanner.swift:74` calls
`FileIndexBuilder.allocatedSize(of: child)` for every candidate a rule finds. That
helper (`FileIndex.swift:173-186`) starts a fresh walk, keeps a `DirNode` per directory
in `TreeMerge.State.nodes`, and throws the tree away except for the root size.
`ScanSession` runs four rules at once (`ScanSession.swift:81` and `135-149`), so four
such maps can be live at the same time.

Cost: O(sum of candidate subtree sizes) metadata I/O, duplicated with the index walk,
and O(directories in the biggest concurrent candidate) memory. The index already
measured every one of these folders. Fix: reuse `FileIndex` tree sizes for rule
candidates, or tag rule matches during the index walk and skip the second walk.

### P1, Homebrew size pass

`ChetCore/Sources/ChetCore/Homebrew.swift:125-153` measures every installed package
with `DispatchQueue.concurrentPerform` and `FS.usage` per keg and per version.
`FS.usage` (`ChetCore/Sources/ChetCore/FS.swift:35-47`) calls `contentsOfDirectory`,
which materializes a full `[URL]` for every folder, and recurses. There is no bound on
concurrent walks (211 packages on this machine).

Measured on the current machine: app 37 MB before Homebrew, 68 MB after the page
loaded, 108 MB peak. That is healthy today, but the work is O(files in every keg) with
one full URL array per directory and one walk per old version. Fix: bound concurrency
to 4, walk each keg once and attribute bytes per version, and cache sizes until the
package list changes.

### P2, quadratic pair searches

- `PerceptualHash.cpuPairs` (`PerceptualHash.swift:143-149`) is O(n^2) comparisons.
  At 100k photos that is 5 x 10^9 hamming distances on the CPU. The GPU path
  (`gpuPairs`) tiles the search but allocates one fixed 1M-pair buffer and throws when
  the cap is exceeded.
- `SimilarVideos.scan` (`SimilarVideos.swift:72-74`) is O(v^2) duration and frame-hash
  comparisons. Videos are fewer, but libraries of thousands still hurt.
- Fix: bucket by hash prefix (multi-index or BK-tree) before pair checks, and turn the
  pair cap into a reported partial result instead of a thrown error.

### P2, treemap layout worst case O(n^2)

`ChetCore/Sources/ChetCore/Treemap.swift:21-27` recomputes the row sum, max, and min
inside `worst` for every item appended, and `worst` is called twice per item. A single
long row makes the squarify pass quadratic. `tiles` and `labels`
(`Chet/Views/DiskMapView.swift:526-596`) call `Treemap.layout` per node and per
relayout, so the same cost repeats on resize and on every live update in a directory
with many children. Fix: carry the row sum, max, and min incrementally.

### P2, per-render O(N) scans in the model

`Chet/ScanModel.swift:217-230` rebuilds a `Set<URL>` over every category item for
`selectedItems` and again for `totalBytes` on each access. SwiftUI reads both from
body views and from the command bar, so each render is O(total items) with a fresh
allocation. `merge` and `add` also sort the category list on every rule result and
step result. Fix: keep `totalBytes`, `selectedBytes`, and per-category totals as
stored values updated on mutation, and sort once when the scan finishes.

### P2, unbounded subprocess output

`ChetCore/Sources/ChetCore/Subprocess.swift:41-49` drains stdout and stderr with
`readDataToEndOfFile`, so memory is O(output). `brew info --json=v2 --installed` is
about 1 MB on this machine, and `brew update`, `upgrade`, and `install` can print more.
Fix: cap captured output (for example 4 MB per stream, keep the tail), since the UI
only shows the first failure message and a line of stdout.

### P2, GPU hasher allocates 64 MB per file

`ChetCore/Sources/ChetCore/GPUHasher.swift:20-26` creates a 64 MiB shared buffer and
an output buffer for every `digest` call. Duplicate hashing with `.gpu` pays that for
every file. Metal keeps freed buffers in its own pool, so peak and fragmentation are
worse than the sizes suggest. Fix: allocate the buffers once per `GPUHasher` and reuse
them, resetting only the counters between files.

### P2, app inventory repeats work

- `AppUninstaller.components` filters matched paths with
  `paths.contains { ancestor in ... }` for every candidate
  (`AppUninstaller.swift:436-442`), which is O(k^2) path-prefix tests.
- `AppCleanerModel.startMeasuringSizes` (`Chet/AppCleanerModel.swift:188-205`) walks
  every app bundle again after discovery, one app at a time. Each walk is a full
  `FileIndexBuilder` with a `DirNode` per directory.
- Fix: sort paths once and keep a stack of kept ancestors for the filter; measure app
  sizes with a bounded pool or reuse the scan index when one exists.

## Reproduction

Build the read-only benchmark and run it on a subtree, never on the whole home folder
without a guard:

```sh
swift build --package-path ChetCore -c release --product chet-scan
/usr/bin/time -l ChetCore/.build/release/chet-scan /Users/wid/Development
```

`chet-scan` exits 1 when peak RSS passes 1.5 GB. The run reported here never reached
that check: it was killed while passing 50 GB, about 34x the budget. Watch a live run
with:

```sh
PID=$(pgrep -n -f 'release/chet-scan')
footprint "$PID"
vmmap --summary "$PID"
heap "$PID"
sample "$PID" 3 -file /tmp/sample.txt
```

The isolated reproduction is 30 lines: `FileHandle(forReadingFrom:)`, loop
`read(upToCount: 1 << 20)`, once without a pool and once inside `autoreleasepool`,
then print `phys_footprint` from `task_info(TASK_VM_INFO)`.

## Order of work

1. `DuplicateFinder`: POSIX reads with reused buffers, plus `autoreleasepool` as the
   immediate guard. This is the 51 GB incident.
2. `DuplicateFinder`: one hash per file, one confirm read, table-based hex.
3. `ScanSession`: bounded, coalesced tree events.
4. `FileIndexBuilder`: build rollup trees only after the filter.
5. `ScanModel`: one mutable tree, cached totals.
6. `RuleScanner`: reuse index sizes instead of re-walking.
7. Homebrew, subprocess, GPU hasher, pair searches, treemap.

## Limits of this review

Numbers are from one machine and one 110 GB tree. The duplicate step's memory does
scale with bytes read, so a larger tree or `.everything` scope makes it worse. The
Homebrew figure was measured on the current installed set (211 packages). No fix is
included in this document; it records evidence and the smallest safe change per
finding.
