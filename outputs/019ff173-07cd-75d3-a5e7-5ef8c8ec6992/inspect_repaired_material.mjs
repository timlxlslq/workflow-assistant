import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "outputs/019ff173-07cd-75d3-a5e7-5ef8c8ec6992/PP0035-2-material-after.xlsx";
const outputPath = "outputs/019ff173-07cd-75d3-a5e7-5ef8c8ec6992/PP0035-2-material-after.png";
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const sheet = workbook.worksheets.getItemAt(0);
const inspection = await workbook.inspect({
  kind: "table,formula,match",
  sheetId: sheet.name,
  range: "A14:I19",
  include: "values,formulas",
  maxChars: 10000,
  tableMaxRows: 10,
  tableMaxCols: 10,
});
console.log(inspection.ndjson);
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 50 },
  summary: "repaired workbook formula error scan",
});
console.log(errors.ndjson);
const preview = await workbook.render({ sheetName: sheet.name, range: "A1:I23", scale: 2, format: "png" });
await fs.writeFile(outputPath, new Uint8Array(await preview.arrayBuffer()));
