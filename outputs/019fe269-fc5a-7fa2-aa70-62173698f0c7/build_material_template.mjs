import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const [sourcePath, outputPath, previewPath] = process.argv.slice(2);
const input = await FileBlob.load(sourcePath);
const workbook = await SpreadsheetFile.importXlsx(input);
const sheet = workbook.worksheets.items[0];

sheet.getRange("A3:I13").clear({ applyTo: "contents" });
sheet.getRange("B1").values = [["ORDER_ID"]];
sheet.getRange("C14:I19").clear({ applyTo: "contents" });
sheet.getRange("C14:H14").formulas = [[
  "=SUM(C3:C13)", "=SUM(D3:D13)", "=SUM(E3:E13)",
  "=SUM(F3:F13)", "=SUM(G3:G13)", "=SUM(H3:H13)",
]];
for (const [row, sourceColumn] of [[17, "F"], [18, "G"], [19, "H"]]) {
  const formulas = [];
  for (const column of ["C", "D", "E", "F", "G", "H", "I"]) {
    formulas.push(`=IF(${column}$16=\"\",\"\",SUMIF($I$3:$I$13,${column}$16,$${sourceColumn}$3:$${sourceColumn}$13))`);
  }
  sheet.getRange(`C${row}:I${row}`).formulas = [formulas];
}

const table = await workbook.inspect({
  kind: "table",
  range: `${sheet.name}!A1:I23`,
  include: "values,formulas",
  tableMaxRows: 23,
  tableMaxCols: 9,
});
process.stdout.write(`${table.ndjson}\n`);
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "material template formula error scan",
});
process.stdout.write(`${errors.ndjson}\n`);
const preview = await workbook.render({
  sheetName: sheet.name,
  range: "A1:I23",
  scale: 2,
  format: "png",
});
await fs.mkdir(path.dirname(previewPath), { recursive: true });
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
