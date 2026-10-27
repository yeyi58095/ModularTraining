"""Append an Artifact Tool-authored slide without reserializing existing slides.

Only package registration metadata and the new slide/notes are changed. Uses
relative hyperlink targets so the USB folder can be moved to another drive.
"""
import copy
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT/'output/meeting_sac_20261027'
NS = {'p':'http://schemas.openxmlformats.org/presentationml/2006/main',
      'a':'http://schemas.openxmlformats.org/drawingml/2006/main',
      'r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
REL='http://schemas.openxmlformats.org/package/2006/relationships'
CT='http://schemas.openxmlformats.org/package/2006/content-types'
for prefix,uri in NS.items(): ET.register_namespace(prefix,uri)


def xml(root):
    if root.tag.startswith('{'+CT+'}'):
        ET.register_namespace('', CT)
    elif root.tag.startswith('{'+REL+'}'):
        ET.register_namespace('', REL)
    return ET.tostring(root,encoding='utf-8',xml_declaration=True)


def main():
    source=PACKAGE/'dist/SAC_Meeting_20261027.pptx'
    authored=PACKAGE/'build/offline-link-slide.pptx'
    candidate=PACKAGE/'build/linked-candidate.pptx'
    with zipfile.ZipFile(source) as z: parts={n:z.read(n) for n in z.namelist()}
    with zipfile.ZipFile(authored) as z: slide=ET.fromstring(z.read('ppt/slides/slide1.xml'))
    assert 'ppt/slides/slide25.xml' not in parts, 'Already appended; edit existing demo slide explicitly.'
    links=[('開啟 SAC 系統架構與程式原文','../docs/index.html'),
           ('開啟 SAC＋LSTM 架構與程式原文','../docs/lstm-explorer.html'),
           ('開啟純 SAC（MLP）架構與程式原文','../docs/mlp-explorer.html'),
           ('開啟補充說明與實驗結果','../docs/report.html')]
    rels=ET.Element(f'{{{REL}}}Relationships')
    oldrels=ET.fromstring(parts['ppt/slides/_rels/slide20.xml.rels'])
    for r in oldrels:
        if r.get('Type','').endswith('/slideLayout'): rels.append(copy.deepcopy(r))
    for i,(label,target) in enumerate(links,1):
        rid=f'rIdOfflineSAC{i}'
        shape=next(s for s in slide.findall('.//p:sp',NS) if ''.join(t.text or '' for t in s.findall('.//a:t',NS))==label)
        nv=shape.find('p:nvSpPr/p:cNvPr',NS)
        nv.insert(0,ET.Element(f'{{{NS["a"]}}}hlinkClick',{f'{{{NS["r"]}}}id':rid}))
        for run in shape.findall('.//a:r',NS):
            props=run.find('a:rPr',NS)
            if props is not None:
                props.set('u','sng')
                ET.SubElement(props,f'{{{NS["a"]}}}hlinkClick',{f'{{{NS["r"]}}}id':rid})
        ET.SubElement(rels,f'{{{REL}}}Relationship',Id=rid,Type=NS['r']+'/hyperlink',Target=target,TargetMode='External')
        assert (source.parent/target).resolve().is_file()
    ET.SubElement(rels,f'{{{REL}}}Relationship',Id='rIdNotesSAC25',Type=NS['r']+'/notesSlide',Target='../notesSlides/notesSlide25.xml')
    with zipfile.ZipFile(authored) as z:
        note_name=next(n for n in z.namelist() if n.startswith('ppt/notesSlides/notesSlide') and n.endswith('.xml'))
        notes=z.read(note_name)
    nr=ET.fromstring(parts['ppt/notesSlides/_rels/notesSlide20.xml.rels'])
    for r in nr:
        if r.get('Type','').endswith('/slide'):r.set('Target','../slides/slide25.xml')
    additions={'ppt/slides/slide25.xml':xml(slide),'ppt/slides/_rels/slide25.xml.rels':xml(rels),
               'ppt/notesSlides/notesSlide25.xml':notes,'ppt/notesSlides/_rels/notesSlide25.xml.rels':xml(nr)}
    presentation=ET.fromstring(parts['ppt/presentation.xml'])
    ids=presentation.find('p:sldIdLst',NS)
    assert len(ids)==24
    ET.SubElement(ids,f'{{{NS["p"]}}}sldId',{'id':str(max(int(x.get('id')) for x in ids)+1),f'{{{NS["r"]}}}id':'rIdOfflineSAC25'})
    pr=ET.fromstring(parts['ppt/_rels/presentation.xml.rels'])
    ET.SubElement(pr,f'{{{REL}}}Relationship',Id='rIdOfflineSAC25',Type=NS['r']+'/slide',Target='slides/slide25.xml')
    ct=ET.fromstring(parts['[Content_Types].xml'])
    for part,kind in [('ppt/slides/slide25.xml','slide'),('ppt/notesSlides/notesSlide25.xml','notesSlide')]:
        ET.SubElement(ct,f'{{{CT}}}Override',PartName='/'+part,ContentType=f'application/vnd.openxmlformats-officedocument.presentationml.{kind}+xml')
    changes={'ppt/presentation.xml':xml(presentation),'ppt/_rels/presentation.xml.rels':xml(pr),'[Content_Types].xml':xml(ct)}
    if 'docProps/app.xml' in parts:
        app=ET.fromstring(parts['docProps/app.xml'])
        for n in app.iter():
            if n.tag.endswith('}Slides'): n.text='25'
        changes['docProps/app.xml']=xml(app)
    with zipfile.ZipFile(candidate,'w',zipfile.ZIP_DEFLATED) as z:
        for n,data in {**parts,**changes,**additions}.items(): z.writestr(n,data)
    with zipfile.ZipFile(candidate) as z:
        assert z.testzip() is None
        for n,data in parts.items():
            if n not in changes: assert z.read(n)==data,n
    receipt=dict(source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),candidate_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest(),
                 preserved_original_parts=len(parts)-len(changes),modified_existing_parts=list(changes),added_parts=list(additions),hyperlinks=links,slides=25)
    (PACKAGE/'build/offline-link-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(receipt,ensure_ascii=False))


if __name__=='__main__':main()
