# The first build session

One sitting. What to write, and what proves it worked.

Land the refusal path end to end, because it is the app's actual unique value and it is 100% provable on the Pi with no Mac, no phone and no AR.

Two repos, one session, in this order.

IN craigm26/duckkit — T-001 and T-002 only. Refactor `DuckPolicy.load` into `describe` + `validate`. `describe(from: Data) throws -> DuckPolicy.Description` walks the protobuf and returns what it found no matter how wrong it is: `ops: [String]`, `initializers: [(name: String, dims: [Int])]`, `inputs`/`outputs` as (name, shape), `parameterCount`, and `gemmTransB: [Bool]`. It throws only when the bytes are not walkable protobuf at all. `load` then calls `describe`, runs the existing architecture checks against the Description, and returns the policy — same LoadError cases, same messages. Also make `mean`/`std` public as `normalization`. The regression proof is that every existing DuckPolicyTests case stays green with zero edits; if one needs editing, the refactor changed behaviour and is wrong.

IN duck-studio — T-010 (partial), T-011, T-012.

Write `scripts/make_refusal_corpus.py`. It reads the vendored `alpha_walking.onnx` (793,705 bytes, already present at CastorKit/Tests/CastorKitTests/Fixtures/duck/alpha_walking.onnx) with the `onnx` Python package and emits seven mutants into `StudioKit/Tests/StudioKitTests/Fixtures/refusals/`, one per distinct rejection reason: (1) a Sigmoid appended after the last Gemm, (2) the second Elu replaced with Relu, (3) `transB` cleared on the third Gemm, (4) the first Gemm's weight widened to 62 inputs, (5) the final Gemm's output narrowed to 13, (6) the `std` initializer deleted, (7) the file truncated at 60% so it dies mid-field. Each mutant gets a one-line note in a sidecar JSON saying what was done and what the app should say about it.

Write `StudioKit/Sources/StudioKit/PolicyReport.swift`. It takes a `DuckPolicy.Description` plus the load outcome and produces the exact strings the Policies screen renders: a headline verdict, a one-sentence reason naming the offending index, and a structural table (op sequence with the divergence marked, initializer names and dims, io shapes, parameter count). No SwiftUI, no formatting helpers borrowed from the app — the text is the product, so the text is what gets tested.

Write `StudioKit/Tests/StudioKitTests/PolicyReportTests.swift` in XCTest, full-sentence camelCase names:
- `testEveryShippedAlphaPolicyLoadsAndReportsTheSameArchitecture`
- `testAnAppendedSigmoidIsRefusedByNamingTheOpAtIndexNine`
- `testAReluInPlaceOfEluIsRefusedByNamingIndexFiveNotJustTheSequence`
- `testAGemmWithoutTransBIsRefusedAndTheReportSaysWhichGemm`
- `testASixtyTwoWideInputIsRefusedAsAShapeErrorNotAnArchitectureError`
- `testATruncatedFileIsRefusedAsMalformedAndStillReportsWhatWasParsed`
- `testTheReportForARefusedFileStillListsEveryInitializerItFound`

The last one is the point of the whole session: a file that fails to load must still produce a useful dump, because the person reading it just spent six hours training that network and needs to know what to change in their export script.

WHAT PROVES IT: `/home/craigm26/swift-6.3.3/usr/bin/swift test` green in StudioKit on the Pi, plus a printed table from a small `swift run`/test-side dump showing all seven real policies with their fingerprint-to-be, parameter count and normalization ranges side by side. If two policies turn out to share a mean/std block, that is itself a finding worth writing down. Nothing in this session needs Xcode, so a bad MacInCloud day cannot block it.
