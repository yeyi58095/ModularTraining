import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from repair_pptx_axis_titles import NS, clean_chart


class AxisTitleRepairTests(unittest.TestCase):
    def test_remove_empty_but_preserve_text_cache_formula_and_chart_title(self):
        xml = f'''<c:chartSpace xmlns:c="{NS['c']}" xmlns:a="{NS['a']}">
        <c:chart><c:title><c:tx><c:rich><a:p><a:r><a:t>Steps</a:t></a:r></a:p></c:rich></c:tx></c:title>
        <c:plotArea><c:catAx><c:title><c:txPr><a:p/></c:txPr></c:title></c:catAx>
        <c:valAx><c:title><c:tx><c:rich><a:p><a:r><a:t>Episode</a:t></a:r></a:p></c:rich></c:tx></c:title></c:valAx>
        <c:valAx><c:title><c:tx><c:strRef><c:f>Sheet1!$A$1</c:f></c:strRef></c:tx></c:title></c:valAx>
        <c:valAx><c:title><c:tx><c:strRef><c:strCache><c:pt idx="0"><c:v>Distance</c:v></c:pt></c:strCache></c:strRef></c:tx></c:title></c:valAx>
        </c:plotArea></c:chart></c:chartSpace>'''.encode()
        fixed, removed = clean_chart(xml)
        self.assertEqual(removed, 1)
        root = ET.fromstring(fixed)
        self.assertIsNotNone(root.find('c:chart/c:title', NS))
        self.assertEqual(len(root.findall('.//c:valAx/c:title', NS)), 3)
        twice, count = clean_chart(fixed)
        self.assertEqual(count, 0)
        self.assertEqual(twice, fixed)


if __name__ == '__main__':
    unittest.main()
