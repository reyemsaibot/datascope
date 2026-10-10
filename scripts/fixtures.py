#!/usr/bin/env python3
"""Deterministic synthetic fixtures; standard library only."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse
root = Path(__file__).resolve().parent.parent / 'Fixtures'
root.mkdir(exist_ok=True)
p = argparse.ArgumentParser()
p.add_argument('--million', action='store_true')
args = p.parse_args()
ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
def cell(ref, value, numeric=False):
    if value is None:
        return ''
    if numeric:
        return f'<c r="{ref}"><v>{value}</v></c>'
    return f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{value}</t></is></c>'
def sheet(rows):
    contents = []
    for i, row in enumerate(rows, 1):
        contents.append(f'<row r="{i}">' + ''.join(cell(f'{chr(65+j)}{i}', v, isinstance(v, (int, float))) for j, v in enumerate(row)) + '</row>')
    return f'<worksheet xmlns="{ns}"><dimension ref="A1:C{len(rows)}"/><sheetData>{"".join(contents)}</sheetData></worksheet>'
with ZipFile(root / 'workbook.xlsx', 'w', ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>''')
    z.writestr('_rels/.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    z.writestr('xl/workbook.xml', f'<workbook xmlns="{ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Kunden" sheetId="1" r:id="rId1"/><sheet name="Umsatz" sheetId="2" r:id="rId2"/></sheets></workbook>')
    z.writestr('xl/_rels/workbook.xml.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + ''.join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in (1,2)) + '</Relationships>')
    z.writestr('xl/worksheets/sheet1.xml', sheet([['id','name','score'],['00123','Anna',10],['00456',None,20],[None,None,None],['00789','Max',30]]))
    z.writestr('xl/worksheets/sheet2.xml', sheet([['id','amount','status'],['0001',12.5,'ok'],['0002',20,'offen']]))
if args.million:
    with (root / 'million.csv').open('w') as f:
        f.write('id,segment,amount,email,city,date,note,active\n')
        for i in range(1_000_000):
            email = '' if i % 10 == 0 else f'user{i}@example.test'
            f.write(f'{i:08d},segment{i%20},{i%10000}.{i%100:02d},{email},city{i%100},2026-01-{i%28+1:02d},note{i%1000},{i%2}\n')
print('Fixtures:', root)
