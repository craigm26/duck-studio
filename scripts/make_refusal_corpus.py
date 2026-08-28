#!/usr/bin/env python3
"""Generate ONNX files that DuckPolicy must refuse, one per distinct reason.

WHY SYNTHESIZE RATHER THAN MUTATE. The obvious approach is to take
alpha_walking.onnx and corrupt it. That works for "truncated" and for nothing
else: changing an op name from Elu to Relu is four bytes where there were three,
so every enclosing length prefix has to be recomputed, and by the time you have
written that you have written a protobuf encoder anyway. Building the files up
from nothing is less code, and it means each fixture contains ONLY the thing it
is testing — a file that is refused for two reasons proves nothing about which
one the message names.

WHY THIS IS THE APP'S VALUE. Duck Studio's single best screen is the one that
says why an export was rejected. That screen can only be trusted if every
refusal is provoked by a file whose defect is known exactly, so these fixtures
are the specification of the refusal text, not an afterthought to it.

The field numbers below are ONNX's, cross-checked against the parser in
DuckKit's DuckPolicy.swift rather than against the spec, because the parser is
what has to walk these:

    ModelProto   7=graph
    GraphProto   1=node  5=initializer  11=input  12=output
    NodeProto    1=input(str)  4=op_type(str)  5=attribute
    AttributeProto 1=name  3=int
    TensorProto  1=dims  2=data_type  8=name  9=raw_data(little-endian f32)

Usage: python3 scripts/make_refusal_corpus.py <output-dir>
"""
from __future__ import annotations

import os
import struct
import sys

FLOAT = 1  # TensorProto.DataType.FLOAT


def varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def tag(field: int, wire: int) -> bytes:
    return varint((field << 3) | wire)


def delimited(field: int, payload: bytes) -> bytes:
    return tag(field, 2) + varint(len(payload)) + payload


def string_field(field: int, text: str) -> bytes:
    return delimited(field, text.encode())


def varint_field(field: int, value: int) -> bytes:
    return tag(field, 0) + varint(value)


def tensor(name: str, dims: list[int], fill: float = 0.01) -> bytes:
    """An initializer. Values are a fixed ramp, not random: a corpus that
    changes every time it is generated cannot be committed and compared."""
    count = 1
    for d in dims:
        count *= d
    raw = b"".join(struct.pack("<f", fill * ((i % 7) + 1)) for i in range(count))
    body = b"".join(varint_field(1, d) for d in dims)
    body += varint_field(2, FLOAT)
    body += string_field(8, name)
    body += delimited(9, raw)
    return body


def node(op: str, inputs: list[str], trans_b: bool = False) -> bytes:
    body = b"".join(string_field(1, i) for i in inputs)
    body += string_field(4, op)
    if trans_b:
        attribute = string_field(1, "transB") + varint_field(3, 1)
        body += delimited(5, attribute)
    return body


def value_info(name: str) -> bytes:
    return string_field(1, name)


def model(nodes: list[bytes], initializers: list[bytes],
          inputs: list[str], outputs: list[str]) -> bytes:
    graph = b"".join(delimited(1, n) for n in nodes)
    graph += b"".join(delimited(5, t) for t in initializers)
    graph += b"".join(delimited(11, value_info(n)) for n in inputs)
    graph += b"".join(delimited(12, value_info(n)) for n in outputs)
    return delimited(7, graph)


# The architecture every alpha policy shares, as widths.
WIDTHS = [(61, 512), (512, 256), (256, 128), (128, 14)]
OPS = ["Sub", "Div", "Gemm", "Elu", "Gemm", "Elu", "Gemm", "Elu", "Gemm"]


def build(ops: list[str] = None, widths=None, obs: int = 61,
          trans_b: bool = True, drop_initializer: str | None = None) -> bytes:
    """A well-formed policy, and every dial needed to make it wrong in exactly
    one way."""
    ops = ops or OPS
    widths = widths or WIDTHS
    widths = [(obs if i == 0 else w[0], w[1]) for i, w in enumerate(widths)]

    initializers = [tensor("mean", [obs]), tensor("std", [obs])]
    nodes = [node("Sub", ["obs", "mean"]), node("Div", ["sub_out", "std"])]

    gemm = 0
    for op in ops[2:]:
        if op == "Gemm":
            i, o = widths[gemm]
            initializers.append(tensor(f"w{gemm}", [o, i]))
            initializers.append(tensor(f"b{gemm}", [o]))
            nodes.append(node("Gemm", [f"h{gemm}", f"w{gemm}", f"b{gemm}"], trans_b=trans_b))
            gemm += 1
        else:
            nodes.append(node(op, [f"g{gemm}"]))

    if drop_initializer:
        initializers = [t for t in initializers if drop_initializer.encode() not in t]

    return model(nodes, initializers, ["obs"], ["actions"])


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-1])
        return 2
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)

    good = build()

    cases: dict[str, bytes] = {
        # --- malformed: the bytes are not walkable ------------------------
        "empty.onnx": b"",
        "truncated.onnx": good[: len(good) * 6 // 10],
        "garbage.onnx": bytes((i * 37 + 11) % 256 for i in range(4096)),
        # Walkable protobuf carrying no graph at all: a ModelProto with only a
        # producer name. Distinct from garbage, and a real thing people upload
        # when an export half-fails.
        "no_graph.onnx": string_field(2, "duck-studio-test"),

        # --- unsupportedArchitecture: walkable, wrong network -------------
        "relu_instead_of_elu.onnx": build(
            ops=["Sub", "Div", "Gemm", "Relu", "Gemm", "Relu", "Gemm", "Relu", "Gemm"]),
        "extra_op_appended.onnx": build(ops=OPS + ["Tanh"]),
        "gemm_without_transb.onnx": build(trans_b=False),

        # --- shape: right network, wrong dimensions -----------------------
        "observation_62_wide.onnx": build(obs=62),
        "output_13_actions.onnx": build(
            widths=[(61, 512), (512, 256), (256, 128), (128, 13)]),
        "hidden_narrowed.onnx": build(
            widths=[(61, 256), (256, 256), (256, 128), (128, 14)]),
    }

    # A control: built the same way, and it must LOAD. Without this the corpus
    # proves only that the builder emits unusable files.
    cases["synthetic_valid.onnx"] = good

    lines = ["# Refusal corpus", "",
             "Generated by `scripts/make_refusal_corpus.py`. Every file is",
             "synthesized, so each one carries exactly one defect.", "",
             "| File | Bytes | Expected |", "|---|---|---|"]
    expectations = {
        "empty.onnx": "malformed",
        "truncated.onnx": "malformed",
        "garbage.onnx": "malformed",
        "no_graph.onnx": "malformed (no graph in ModelProto)",
        "relu_instead_of_elu.onnx": "unsupportedArchitecture (op sequence)",
        "extra_op_appended.onnx": "unsupportedArchitecture (op sequence)",
        "gemm_without_transb.onnx": "unsupportedArchitecture (Gemm without transB=1)",
        "observation_62_wide.onnx": "shape",
        "output_13_actions.onnx": "shape",
        "hidden_narrowed.onnx": "shape",
        "synthetic_valid.onnx": "LOADS — the control",
    }
    for name in sorted(cases):
        data = cases[name]
        with open(os.path.join(out, name), "wb") as handle:
            handle.write(data)
        lines.append(f"| `{name}` | {len(data)} | {expectations[name]} |")

    with open(os.path.join(out, "README.md"), "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"wrote {len(cases)} files to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
