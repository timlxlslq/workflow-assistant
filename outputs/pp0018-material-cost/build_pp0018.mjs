import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const dataPath = "outputs/pp0018-material-cost/material_data.json";
const outputDir = "outputs/pp0018-material-cost";
const outputPath = `${outputDir}/PP0018_material_cost_by_room.xlsx`;
const previewDir = `${outputDir}/previews`;
const data = JSON.parse(await fs.readFile(dataPath, "utf8"));

const workbook = Workbook.create();
const summary = workbook.worksheets.add("材料成本汇总");
const priceSheet = workbook.worksheets.add("价格与来源");
summary.showGridLines = false;
priceSheet.showGridLines = false;

const navy = "#1F4E78";
const blue = "#D9EAF7";
const paleBlue = "#EEF5FB";
const gray = "#F3F4F6";
const border = "#B8C7D9";
const redFill = "#FDE2E2";
const redFont = "#B91C1C";
const greenFill = "#E8F5E9";

const orderedRooms = data.room_summaries.map((item) => item.room);

summary.getRange("A1:L1").merge();
summary.getRange("A1").values = [["PP0018 材料成本汇总"]];
summary.getRange("A1:L1").format = {
  fill: navy,
  font: { bold: true, color: "#FFFFFF", size: 16 },
  horizontalAlignment: "center",
  verticalAlignment: "center",
};
summary.getRange("A1:L1").format.rowHeight = 30;
summary.getRange("A2:L2").merge();
summary.getRange("A2").values = [[data.method_note]];
summary.getRange("A2:L2").format = {
  fill: paleBlue,
  font: { color: "#334155", italic: true, size: 10 },
  wrapText: true,
  verticalAlignment: "center",
};
summary.getRange("A2:L2").format.rowHeight = 34;

summary.getRange("A4:B4").merge();
summary.getRange("A4").values = [["房间数"]];
summary.getRange("A5:B5").merge();
summary.getRange("A5").formulas = [["=COUNTA(A10:A200)"]];
summary.getRange("D4:E4").merge();
summary.getRange("D4").values = [["材料明细行数"]];
summary.getRange("D5:E5").merge();
summary.getRange("D5").formulas = [["=COUNTA(C10:C200)"]];
summary.getRange("G4:H4").merge();
summary.getRange("G4").values = [["未知价格行数"]];
summary.getRange("G5:H5").merge();
summary.getRange("G5").formulas = [["=COUNTIF(J10:J200,\"未知价格\")"]];
summary.getRange("J4:K4").merge();
summary.getRange("J4").values = [["总成本"]];
summary.getRange("J5:K5").merge();

for (const rangeAddress of ["A4:B4", "D4:E4", "G4:H4", "J4:K4"]) {
  summary.getRange(rangeAddress).format = {
    fill: blue,
    font: { bold: true, color: navy },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
}
for (const rangeAddress of ["A5:B5", "D5:E5", "G5:H5", "J5:K5"]) {
  summary.getRange(rangeAddress).format = {
    fill: "#FFFFFF",
    font: { bold: true, color: navy, size: 14 },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: border },
  };
}
summary.getRange("J5").formulas = [["=SUM(I10:I200)"]];
summary.getRange("J5:K5").setNumberFormat('"$"#,##0.00');

const headers = [["房间", "来源文件", "材料名称", "规格", "商品编号", "单位", "汇总数量", "单价", "材料成本", "价格状态", "数量来源", "价格说明"]];
summary.getRange("A8:L8").values = headers;
summary.getRange("A8:L8").format = {
  fill: navy,
  font: { bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  wrapText: true,
  borders: { preset: "outside", style: "thin", color: navy },
};
summary.getRange("A8:L8").format.rowHeight = 28;

let rowNumber = 9;
const subtotalRows = [];
const materialRowsByStatus = [];
for (const room of orderedRooms) {
  const materialRows = data.rows.filter((row) => row.room === room);
  const roomStart = rowNumber;
  for (const item of materialRows) {
    summary.getRange(`A${rowNumber}:L${rowNumber}`).values = [[
      item.room,
      item.source_files.join("\n"),
      item.material_name,
      item.spec,
      item.code,
      item.unit || (item.material_name.startsWith("Edge banding") ? "M" : "SHT"),
      item.quantity,
      item.price,
      null,
      item.price_status,
      item.quantity_sources.join("；"),
      item.price_note,
    ]];
    summary.getRange(`I${rowNumber}`).formulas = [[`=G${rowNumber}*H${rowNumber}`]];
    summary.getRange(`A${rowNumber}:L${rowNumber}`).format = {
      fill: item.price_status === "未知价格" ? redFill : "#FFFFFF",
      font: { color: item.price_status === "未知价格" ? redFont : "#1F2937" },
      verticalAlignment: "center",
      wrapText: true,
      borders: { preset: "inside", style: "thin", color: "#E5E7EB" },
    };
    if (item.price_status === "未知价格") materialRowsByStatus.push(rowNumber);
    rowNumber += 1;
  }
  const subtotalRow = rowNumber;
  subtotalRows.push(subtotalRow);
  summary.getRange(`A${subtotalRow}:H${subtotalRow}`).merge();
  summary.getRange(`A${subtotalRow}`).values = [[`${room} 小计`]];
  summary.getRange(`I${subtotalRow}`).formulas = [[`=SUM(I${roomStart}:I${subtotalRow - 1})`]];
  summary.getRange(`J${subtotalRow}:L${subtotalRow}`).merge();
  summary.getRange(`J${subtotalRow}`).values = [["房间材料成本"]];
  summary.getRange(`A${subtotalRow}:L${subtotalRow}`).format = {
    fill: blue,
    font: { bold: true, color: navy },
    verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: border },
  };
  rowNumber += 1;
}

const grandTotalRow = rowNumber + 1;
summary.getRange(`A${grandTotalRow}:H${grandTotalRow}`).merge();
summary.getRange(`A${grandTotalRow}`).values = [["PP0018 全部房间总计"]];
summary.getRange(`I${grandTotalRow}`).formulas = [[`=SUM(${subtotalRows.map((row) => `I${row}`).join(",")})`]];
summary.getRange(`J${grandTotalRow}:L${grandTotalRow}`).merge();
summary.getRange(`J${grandTotalRow}`).values = [["未知价格按 $0.00 计入"]];
summary.getRange(`A${grandTotalRow}:L${grandTotalRow}`).format = {
  fill: navy,
  font: { bold: true, color: "#FFFFFF", size: 12 },
  verticalAlignment: "center",
  borders: { preset: "outside", style: "medium", color: navy },
};
summary.getRange(`J${grandTotalRow}`).format.horizontalAlignment = "center";
summary.getRange(`I${grandTotalRow}`).setNumberFormat('"$"#,##0.00');
summary.getRange("A5").formulas = [[`=COUNTIF(J9:J${grandTotalRow},"房间材料成本")`]];
summary.getRange("D5").formulas = [[`=COUNTIF(J9:J${grandTotalRow},"已知")+COUNTIF(J9:J${grandTotalRow},"未知价格")`]];
summary.getRange("G5").formulas = [[`=COUNTIF(J9:J${grandTotalRow},"未知价格")`]];
summary.getRange("J5").formulas = [[`=I${grandTotalRow}`]];
summary.getRange(`G9:G${grandTotalRow}`).setNumberFormat("#,##0.00");
summary.getRange(`H9:I${grandTotalRow}`).setNumberFormat('"$"#,##0.00');
summary.getRange("A5").setNumberFormat("0");
summary.getRange("D5").setNumberFormat("0");
summary.getRange("G5").setNumberFormat("0");
summary.getRange(`A9:L${grandTotalRow}`).format.rowHeight = 36;
summary.getRange(`A9:L${grandTotalRow}`).format.borders = {
  insideHorizontal: { style: "thin", color: "#E5E7EB" },
  outside: { style: "thin", color: border },
};
summary.freezePanes.freezeRows(8);

const widths = {
  A: 34, B: 42, C: 25, D: 16, E: 12, F: 10,
  G: 13, H: 12, I: 14, J: 12, K: 28, L: 42,
};
for (const [column, width] of Object.entries(widths)) {
  summary.getRange(`${column}1:${column}${grandTotalRow}`).format.columnWidth = width;
}

priceSheet.getRange("A1:J1").merge();
priceSheet.getRange("A1").values = [["PP0018 材料价格与来源"]];
priceSheet.getRange("A1:J1").format = {
  fill: navy,
  font: { bold: true, color: "#FFFFFF", size: 15 },
  horizontalAlignment: "center",
  verticalAlignment: "center",
};
priceSheet.getRange("A2:J2").merge();
priceSheet.getRange("A2").values = [[`价格来源：${data.catalog_path}；价格字段：${data.catalog_price_field}。SQLite products 表未保存价格，因此本表使用当前库存商品资料中的该字段。`]];
priceSheet.getRange("A2:J2").format = {
  fill: paleBlue,
  font: { color: "#334155", italic: true, size: 10 },
  wrapText: true,
};
priceSheet.getRange("A2:J2").format.rowHeight = 32;
priceSheet.getRange("A4:J4").values = [["材料名称", "商品编号", "商品名称", "商品规格", "单位", "单价", "价格状态", "价格说明", "价格文件", "价格字段"]];
priceSheet.getRange("A4:J4").format = {
  fill: navy,
  font: { bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center",
  verticalAlignment: "center",
  wrapText: true,
};
const uniquePriceRows = [];
const seenPriceKeys = new Set();
for (const item of data.rows) {
  if (seenPriceKeys.has(item.material_name)) continue;
  seenPriceKeys.add(item.material_name);
  uniquePriceRows.push(item);
}
for (let index = 0; index < uniquePriceRows.length; index += 1) {
  const item = uniquePriceRows[index];
  const row = 5 + index;
  priceSheet.getRange(`A${row}:J${row}`).values = [[
    item.material_name,
    item.code,
    item.product_name,
    item.product_spec,
    item.unit,
    item.price,
    item.price_status,
    item.price_note,
    data.catalog_path,
    data.catalog_price_field,
  ]];
  priceSheet.getRange(`A${row}:J${row}`).format = {
    fill: item.price_status === "未知价格" ? redFill : "#FFFFFF",
    font: { color: item.price_status === "未知价格" ? redFont : "#1F2937" },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "inside", style: "thin", color: "#E5E7EB" },
  };
}
const lastPriceRow = 4 + uniquePriceRows.length;
priceSheet.getRange(`F5:F${lastPriceRow}`).setNumberFormat('"$"#,##0.00');
priceSheet.getRange(`A5:J${lastPriceRow}`).format.rowHeight = 34;
priceSheet.freezePanes.freezeRows(4);
for (const [column, width] of Object.entries({ A: 28, B: 12, C: 28, D: 28, E: 10, F: 12, G: 12, H: 42, I: 64, J: 16 })) {
  priceSheet.getRange(`${column}1:${column}${lastPriceRow}`).format.columnWidth = width;
}

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

for (const [sheetName, range] of [["材料成本汇总", `A1:L${grandTotalRow}`], ["价格与来源", `A1:J${lastPriceRow}`]]) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(`${previewDir}/${sheetName}.png`, new Uint8Array(await preview.arrayBuffer()));
}

const check = await workbook.inspect({
  kind: "table",
  range: `材料成本汇总!A1:L${grandTotalRow}`,
  include: "values,formulas",
  tableMaxRows: 12,
  tableMaxCols: 12,
  maxChars: 10000,
});
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});
console.log(JSON.stringify({ outputPath, grandTotalRow, lastPriceRow, inspect: check.ndjson, errors: errors.ndjson }, null, 2));
