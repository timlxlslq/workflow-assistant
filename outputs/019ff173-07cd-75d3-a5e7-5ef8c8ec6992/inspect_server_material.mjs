import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "/Volumes/server/Optimized Orders/pp0035-2/PP0035-2 materials.xlsx";
const outputDir = "/Users/lantian/Documents/工作流程助手/outputs/019ff173-07cd-75d3-a5e7-5ef8c8ec6992";
const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);
const overview = await workbook.inspect({
  kind: "workbook,sheet,table,formula,computedStyle",
  maxChars: 18000,
  tableMaxRows: 30,
  tableMaxCols: 12,
  tableMaxCellChars: 100,
});
console.log("OVERVIEW\n" + overview.ndjson);
const sheet = workbook.worksheets.getItemAt(0);
for (const range of ["A1:I23", "A3:I14", "A15:I19"]) {
  const inspection = await workbook.inspect({
    kind: "table,formula,computedStyle",
    sheetId: sheet.name,
    range,
    include: "values,formulas",
    maxChars: 12000,
    tableMaxRows: 30,
    tableMaxCols: 12,
  });
  console.log(`RANGE ${range}\n${inspection.ndjson}`);
}
const preview = await workbook.render({ sheetName: sheet.name, range: "A1:I23", scale: 2, format: "png" });
await fs.writeFile(`${outputDir}/PP0035-2-material-before.png`, new Uint8Array(await preview.arrayBuffer()));
