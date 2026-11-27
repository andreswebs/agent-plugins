# /// script
# requires-python = ">=3.9"
# dependencies = ["pdf-inspector==1.25.2"]
# ///
"""Classify one PDF copy without extracting or recognising its text.

Usage: uv run classify_pdf.py <file.pdf>

Prints one JSON object with the four manifest fields, keys in this order:
pdf_type ("text", "scanned", "image", "mixed"), confidence (0.0 to 1.0),
pages_needing_ocr (1-indexed page numbers), encoding_broken (true or false).

Exit 0: classified. Exit 1: usage error or file not readable, nothing
printed on stdout. Exit 2: the classifier failed on the file; every field
is printed as "unknown".
"""

import json
import sys
from pathlib import Path

PDF_TYPES = {
    "text_based": "text",
    "scanned": "scanned",
    "image_based": "image",
    "mixed": "mixed",
}
UNKNOWN = {
    "pdf_type": "unknown",
    "confidence": "unknown",
    "pages_needing_ocr": "unknown",
    "encoding_broken": "unknown",
}


def classify(pdf: Path) -> dict:
    import pdf_inspector

    result = pdf_inspector.detect_pdf(str(pdf))
    encoding_broken = getattr(result, "has_encoding_issues", None)
    return {
        "pdf_type": PDF_TYPES.get(result.pdf_type, "unknown"),
        "confidence": round(float(result.confidence), 3),
        "pages_needing_ocr": sorted(int(page) for page in result.pages_needing_ocr),
        "encoding_broken": "unknown" if encoding_broken is None else bool(encoding_broken),
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__, file=sys.stderr)
        return 0 if len(argv) == 2 else 1
    pdf = Path(argv[1])
    if not pdf.is_file():
        print(f"not a file: {pdf}", file=sys.stderr)
        return 1
    try:
        fields = classify(pdf)
    # A fetch must survive any classifier failure, so the fields degrade to "unknown".
    except Exception as error:  # noqa: BLE001
        print(f"classifier failed: {error}", file=sys.stderr)
        print(json.dumps(UNKNOWN))
        return 2
    print(json.dumps(fields))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
