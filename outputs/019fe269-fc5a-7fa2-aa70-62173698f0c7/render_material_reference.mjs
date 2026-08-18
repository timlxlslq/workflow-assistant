import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const [inputPath, outputDir] = process.argv.slice(2);
await fs.mkdir(outputDir, { recursive: true });
const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);
const sheetName = workbook.worksheets.items[0].name;
const table = await workbook.inspect({
  kind: "table",
  range: `${sheetName}!A1:I23`,
  include: "values,formulas",
  tableMaxRows: 23,
  tableMaxCols: 9,
});
process.stdout.write(`${table.ndjson}\n`);
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "material formula error scan",
});
process.stdout.write(`${errors.ndjson}\n`);
const preview = await workbook.render({
  sheetName,
  range: "A1:I23",
  scale: 2,
  format: "png",
});
await fs.writeFile(`${outputDir}/manual-material-reference.png`, new Uint8Array(await preview.arrayBuffer()));
