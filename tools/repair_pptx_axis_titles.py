"""Remove empty chart-axis title elements that PowerPoint displays as placeholders.

Preserves real titles, chart data, workbooks and all other package parts. Creates
a new PPTX; never overwrites the source or an existing destination. Stdlib only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

NS = {
    'c': 'http://schemas.openxmlformats.org/drawingml/2006/chart',
    'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
    'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
}
for prefix, uri in NS.items():
    ET.register_namespace(prefix, uri)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def clean_chart(data):
    root = ET.fromstring(data)
    removed = 0
    for axis_type in ('catAx', 'valAx', 'dateAx', 'serAx'):
        for axis in root.findall('.//c:' + axis_type, NS):
            for title in list(axis.findall('c:title', NS)):
                visible = ''.join(t.text or '' for t in title.findall('.//a:t', NS)).strip()
                cached = ''.join(t.text or '' for t in title.findall('.//c:v', NS)).strip()
                # Formula-backed titles may have no cache; retain their semantics.
                if not visible and not cached and title.find('.//c:f', NS) is None:
                    axis.remove(title)
                    removed += 1
    if not removed:
        return data, 0
    return ET.tostring(root, encoding='utf-8', xml_declaration=True), removed


def repair(source, destination):
    source = Path(source).resolve()
    destination = Path(destination).resolve()
    if source == destination or destination.exists():
        raise FileExistsError('Use a new destination filename; source is never overwritten')
    source_hash = sha(source.read_bytes())
    changes = []
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, 'x') as output:
        names = original.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate package parts')
        for info in original.infolist():
            data = original.read(info.filename)
            if re.search(r'/charts/[^/]+\.xml$', info.filename):
                data, count = clean_chart(data)
                if count:
                    changes.append({'part': info.filename, 'empty_axis_titles_removed': count})
            output.writestr(info, data)
    # Reopen and verify: unchanged package parts, including embedded workbooks,
    # must match byte-for-byte. Each chart must equal exactly the intended repair.
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination) as repaired:
        assert original.namelist() == repaired.namelist()
        assert repaired.testzip() is None
        for name in original.namelist():
            expected = original.read(name)
            if re.search(r'/charts/[^/]+\.xml$', name):
                expected, _ = clean_chart(expected)
                _, remaining = clean_chart(repaired.read(name))
                assert remaining == 0, name
            assert repaired.read(name) == expected, name
    assert sha(source.read_bytes()) == source_hash
    return {
        'source': str(source), 'source_sha256': source_hash,
        'output': str(destination), 'output_sha256': sha(destination.read_bytes()),
        'chart_parts_changed': len(changes),
        'empty_axis_titles_removed': sum(c['empty_axis_titles_removed'] for c in changes),
        'changes': changes,
        'verification': 'All non-chart parts byte-identical; chart edits limited to removing empty axis title elements',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        raise FileExistsError(args.report)
    result = repair(args.source, args.destination)
    with args.report.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
    print(f"Removed {result['empty_axis_titles_removed']} empty axis titles across {result['chart_parts_changed']} charts")


if __name__ == '__main__':
    main()
