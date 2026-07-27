import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = process.argv[2];
const outputDir = process.argv[3];
if (!inputPath || !outputDir) throw new Error("usage: verify_workbook.mjs input.xlsx output-dir");

await fs.mkdir(outputDir, { recursive: true });
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const summary = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 8000,
  tableMaxRows: 24,
  tableMaxCols: 12,
});
console.log(summary.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "formula error scan",
});
console.log(errors.ndjson);

for (const name of ["WorkOrderTraveler", "Pickinglist", "Purchase List", "Cuttinglist", "Packing and Sorting List"]) {
  const preview = await workbook.render({ sheetName: name, autoCrop: "all", scale: 1, format: "png" });
  const safe = name.replaceAll(" ", "-");
  await fs.writeFile(path.join(outputDir, `${safe}.png`), new Uint8Array(await preview.arrayBuffer()));
}
