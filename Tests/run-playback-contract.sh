#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/bilive-ios-contract.XXXXXX)
binary="$work/contract"
python3 - "$work/HistoryEntry.swift" <<'PYCODE'
from pathlib import Path
import sys
s = Path("Live OS/Live OS/Views/HistoryView.swift").read_text()
Path(sys.argv[1]).write_text("import Foundation\n" + s[s.index("struct HistoryEntry:"):s.index("#Preview", s.index("struct HistoryEntry:"))])
PYCODE
trap 'rm -rf "$work"' EXIT
xcrun swiftc -parse-as-library 'Live OS/Live OS/Models/'*.swift 'Live OS/Live OS/Network/APIClient.swift' "$work/HistoryEntry.swift" 'Live OS/Live OS/ViewModels/VideoLibraryViewModel.swift' Tests/ModelPlatformStubs.swift Tests/PlaybackContractTests.swift -o "$binary"
"$binary"
