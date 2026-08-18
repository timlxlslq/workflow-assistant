# 工作流程助手真实启动扫描 Server 追踪（2026-08-14）

## 执行范围

- 真实打开：/Applications/工作流程助手.app
- 自动启动流程：读取本地索引 → AIMES 今日缓存检查 → scan-server → sync-index → 更新看板
- 未点击“扫描 Server”，未处理待处理变化，未生成 Traveler，未出库。
- 电源适配器供电时的自动锁定设置：当前为“永不”，按用户要求暂不恢复。

## 第一次真实 App 启动：完整流程

| 时间（PDT） | 步骤 | 后端耗时 | 实际动作 |
|---|---|---:|---|
| 10:04:00.875–10:04:00.901 | 读取本地索引 | 0.026 秒 | 读取 order-index.sqlite3 中的订单看板数据 |
| 10:04:01.252–10:04:01.279 | AIMES 检查 | 0.027 秒（界面显示0.36秒） | 发现今天已经成功获取过 AIMES，因此使用缓存，未重新请求 |
| 10:04:01.573–10:04:11.857 | 扫描 Server | 10.284 秒 | 遍历两个 Server 根目录，比较订单文件夹及 Excel 的路径、修改时间、大小 |
| 10:04:12.175–10:05:16.671 | 更新订单索引 | 64.496 秒（SQLite记录约64秒） | 读取/解析当前订单报表，更新订单、工厂单、报表状态和校验结果 |
| 10:05:16.671–约10:05:17.01 | 更新看板 | 约0.34秒 | 将后端结果应用到 SwiftUI 看板 |

App 界面最终显示：“Server 扫描完成，没有待处理变化（用时 64.81 秒）”；“订单索引已更新（用时 0.34 秒）”。

## Server 扫描结果

- 根目录：/Volumes/server/Optimized Orders
- 根目录：/Volumes/server/CUT TO SIZE
- 订单文件夹：14 个
- 唯一业务 Excel：112 个
  - 板材清单：50 个
  - Fittingslist：50 个
  - material：12 个
- 新增：0
- 修改：0
- 删除：0
- 扫描阶段没有打开 Excel 内容；它只读取目录和文件元数据进行比对。
- 后面的 sync-index 才对这 112 个唯一业务文件进行解析；部分文件会因订单校验而被重复读取。

## 第一次流程的数据库写入

数据库：/Users/lantian/Documents/工作流程助手/data/order-index.sqlite3

### scan-server 阶段

后端操作日志记录了：

- source_files：7 次 DELETE 尝试
- active_issues：7 次 UPDATE 尝试
- orders：1 次 UPDATE

这些是旧临时目录状态清理及订单状态维护；扫描结果本身没有新增、修改或删除 Server 文件。

### sync-index 阶段

操作日志记录了：

- source_files：126 次 INSERT、95 次 UPDATE
- orders：51 次 INSERT、14 次 UPDATE
- factory_orders：19 次 INSERT、27 次 UPDATE
- active_issues：8 次 UPDATE
- aimes_review_rows：1 次 DELETE
- sync_changes：3 次 INSERT
- sync_runs：1 次 INSERT

其中 126 次 source_files INSERT 对应 14 个订单文件夹加 112 个业务 Excel。操作日志只记录表名和操作类型，不记录每条 SQL 的绑定值；下面的文件清单来自本次同步后 source_files.last_seen = 2026-08-14T10:04:12 的实际记录。

## 本次同步涉及的完整文件清单

### /Volumes/server/CUT TO SIZE/cs001（3 个 Excel）

- 板材清单：<code>/Volumes/server/CUT TO SIZE/cs001/Report/pp-板材清单-newPC124429962606300004.xlsx</code>
- Fittingslist：<code>/Volumes/server/CUT TO SIZE/cs001/Report/FittingslistPC124429962606300004.xlsx</code>
- 订单文件夹：<code>/Volumes/server/CUT TO SIZE/cs001</code>
- material：<code>/Volumes/server/CUT TO SIZE/cs001/CS001 materials.xlsx</code>

### /Volumes/server/CUT TO SIZE/cs002（0 个 Excel）

- 订单文件夹：<code>/Volumes/server/CUT TO SIZE/cs002</code>

### /Volumes/server/CUT TO SIZE/cs003（3 个 Excel）

- 板材清单：<code>/Volumes/server/CUT TO SIZE/cs003/cs003 woodline4/Report/pp-板材清单-newPC124429962607230002.xlsx</code>
- Fittingslist：<code>/Volumes/server/CUT TO SIZE/cs003/cs003 woodline4/Report/FittingslistPC124429962607230002.xlsx</code>
- 订单文件夹：<code>/Volumes/server/CUT TO SIZE/cs003</code>
- material：<code>/Volumes/server/CUT TO SIZE/cs003/CS003 materials.xlsx</code>

### /Volumes/server/CUT TO SIZE/cs004（3 个 Excel）

- 板材清单：<code>/Volumes/server/CUT TO SIZE/cs004/CS004-KITCHEN_20260803145629/Report/pp-板材清单-newPC124429962607310001.xlsx</code>
- Fittingslist：<code>/Volumes/server/CUT TO SIZE/cs004/CS004-KITCHEN_20260803145629/Report/FittingslistPC124429962607310001.xlsx</code>
- 订单文件夹：<code>/Volumes/server/CUT TO SIZE/cs004</code>
- material：<code>/Volumes/server/CUT TO SIZE/cs004/cs004 material.xlsx</code>

### /Volumes/server/CUT TO SIZE/cs005（2 个 Excel）

- 板材清单：<code>/Volumes/server/CUT TO SIZE/cs005/CS005-KITCHEN_woodline 4/Report/pp-板材清单-newPC124429962608120001.xlsx</code>
- Fittingslist：<code>/Volumes/server/CUT TO SIZE/cs005/CS005-KITCHEN_woodline 4/Report/FittingslistPC124429962608120001.xlsx</code>
- 订单文件夹：<code>/Volumes/server/CUT TO SIZE/cs005</code>

### /Volumes/server/Optimized Orders/mario extracabinets（3 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/mario extracabinets/Report/pp-板材清单-new.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/mario extracabinets/Report/Fittingslist.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/mario extracabinets</code>
- material：<code>/Volumes/server/Optimized Orders/mario extracabinets/MARIO EXTRACABINETS materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0035（25 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 bathsravenoak doors new/Report/pp-板材清单PC124429962606170004.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 hallway body/Report/pp-板材清单-newPC124429962606250001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 hallway doors/Report/pp-板材清单-newPC124429962606250001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 kitchen1_laundry/Report/pp-板材清单PC124429962606170004.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 mainkitchen body/Report/pp-板材清单-newPC124429962606270001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 mainkitchendoors/Report/pp-板材清单-newPC124429962607080001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 masterbathnew/Report/pp-板材清单-newPC124429962607140001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 mastercloset/Report/pp-板材清单PC124429962606170004.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035-baths1_3_4_5/Report/pp-板材清单PC124429962606170004.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035bedroom 1-5 body/Report/pp-板材清单PC124429962606190001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035bedroom 1-5 doors/Report/pp-板材清单PC124429962606190001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035/pp0035masterbath_powderroom/Report/pp-板材清单-newPC124429962606170004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 bathsravenoak doors new/Report/FittingslistPC124429962606170004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 hallway body/Report/FittingslistPC124429962606250001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 hallway doors/Report/FittingslistPC124429962606250001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 kitchen1_laundry/Report/FittingslistPC124429962606170004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 mainkitchen body/Report/FittingslistPC124429962606270001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 mainkitchendoors/Report/FittingslistPC124429962607080001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 masterbathnew/Report/FittingslistPC124429962607140001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035 mastercloset/Report/FittingslistPC124429962606170004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035-baths1_3_4_5/Report/FittingslistPC124429962606170004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035bedroom 1-5 body/Report/FittingslistPC124429962606190001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035bedroom 1-5 doors/Report/FittingslistPC124429962606190001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035/pp0035masterbath_powderroom/Report/FittingslistPC124429962606170004.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0035</code>
- material：<code>/Volumes/server/Optimized Orders/pp0035/PP0035 materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0035-2（7 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035-2/PP0035-2 OPENSHELF_20260728105647/Report/pp-板材清单-newPC124429962607290001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035-2/PP0035-OFFICE_khaki/Report/pp-板材清单-newPC124429962608050001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0035-2/PP0035-OFFICE_pp0035-2 mastercloset body+frappe3/Report/pp-板材清单-newPC124429962608050001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035-2/PP0035-2 OPENSHELF_20260728105647/Report/FittingslistPC124429962607290001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035-2/PP0035-OFFICE_khaki/Report/FittingslistPC124429962608050001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0035-2/PP0035-OFFICE_pp0035-2 mastercloset body+frappe3/Report/FittingslistPC124429962608050001.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0035-2</code>
- material：<code>/Volumes/server/Optimized Orders/pp0035-2/PP0035-2 materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0046（3 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0046/pp0046 1st_2nd_master autolabel/Report/pp-板材清单-newPC124429962607230001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0046/pp0046 1st_2nd_master autolabel/Report/FittingslistPC124429962607230001.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0046</code>
- material：<code>/Volumes/server/Optimized Orders/pp0046/pp0046 materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0047（43 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-POWDERROOM_20260724150933/Report/pp-板材清单-newPC124429962607240001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/pp-板材清单-newPC124429962607100001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/pp-板材清单-newPC124429962607120002.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/pp-板材清单-newPC124429962607160003.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/pp-板材清单-newPC124429962607160004.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-drawers/Report/pp-板材清单-newPC124429962607100001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-drawers/Report/pp-板材清单-newPC124429962607160003.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-drawers/Report/pp-板材清单-newPC124429962607160004.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath DRAWER HOLES ONLY/Report/pp-板材清单-newPC124429962607160003.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath_vanity/Report/pp-板材清单-newPC124429962607100001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath_vanity_drawer HOLES ONLY/Report/pp-板材清单-newPC124429962607100001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath_vanity_drawer HOLES ONLY/Report/pp-板材清单-newPC124429962607160003.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbathnew/Report/pp-板材清单-newPC124429962607160003.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 pantry_laundry_vanity woodline4DOORS/Report/pp-板材清单-newPC124429962607100001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 pantry_laundry_vanity woodline4DOORS/Report/pp-板材清单-newPC124429962607120002.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 pantry_laundry_vanity woodline4DOORS/Report/pp-板材清单-newPC124429962607160004.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 vanity backing/Report/pp-板材清单-newPC124429962607100001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047kitchen/Report/pp-板材清单-newPC124429962607020002.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047pantry_laundry_vanitypantry BODY/Report/pp-板材清单-newPC124429962607100001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047pantry_laundry_vanitypantry BODY/Report/pp-板材清单-newPC124429962607120002.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0047/pp0047pantry_laundry_vanitypantry BODY/Report/pp-板材清单-newPC124429962607160004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-POWDERROOM_20260724150933/Report/FittingslistPC124429962607240001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/FittingslistPC124429962607100001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/FittingslistPC124429962607120002.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/FittingslistPC124429962607160003.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-backings/Report/FittingslistPC124429962607160004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-drawers/Report/FittingslistPC124429962607100001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-drawers/Report/FittingslistPC124429962607160003.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/PP0047-drawers/Report/FittingslistPC124429962607160004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath DRAWER HOLES ONLY/Report/FittingslistPC124429962607160003.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath_vanity/Report/FittingslistPC124429962607100001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath_vanity_drawer HOLES ONLY/Report/FittingslistPC124429962607100001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbath_vanity_drawer HOLES ONLY/Report/FittingslistPC124429962607160003.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 masterbathnew/Report/FittingslistPC124429962607160003.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 pantry_laundry_vanity woodline4DOORS/Report/FittingslistPC124429962607100001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 pantry_laundry_vanity woodline4DOORS/Report/FittingslistPC124429962607120002.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 pantry_laundry_vanity woodline4DOORS/Report/FittingslistPC124429962607160004.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047 vanity backing/Report/FittingslistPC124429962607100001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047kitchen/Report/FittingslistPC124429962607020002.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047pantry_laundry_vanitypantry BODY/Report/FittingslistPC124429962607100001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047pantry_laundry_vanitypantry BODY/Report/FittingslistPC124429962607120002.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0047/pp0047pantry_laundry_vanitypantry BODY/Report/FittingslistPC124429962607160004.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0047</code>
- material：<code>/Volumes/server/Optimized Orders/pp0047/PP0047 materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0063-2（11 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2- CashmereSM NEWCNC/Report/pp-板材清单-newPC124429962607280001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2-Box All/Report/pp-板材清单-newPC124429962607280001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2-Walnut New/Report/pp-板材清单-newPC124429962607280001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2-khaki NEW/Report/pp-板材清单-newPC124429962607280001.xlsx</code>
- 板材清单：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-Backing OLD CNC/Report/pp-板材清单-newPC124429962607280001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2- CashmereSM NEWCNC/Report/FittingslistPC124429962607280001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2-Box All/Report/FittingslistPC124429962607280001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2-Walnut New/Report/FittingslistPC124429962607280001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-2-khaki NEW/Report/FittingslistPC124429962607280001.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0063-2/PP0063-Backing OLD CNC/Report/FittingslistPC124429962607280001.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0063-2</code>
- material：<code>/Volumes/server/Optimized Orders/pp0063-2/pp0063-2 materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0065（3 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0065/pp0065 closetfixed/Report/pp-板材清单-newPC124429962607210002.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0065/pp0065 closetfixed/Report/FittingslistPC124429962607210002.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0065</code>
- material：<code>/Volumes/server/Optimized Orders/pp0065/pp0065 materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0067（3 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0067/PP0067-floating shelves/Report/pp-板材清单-newPC124429962607280002.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0067/PP0067-floating shelves/Report/FittingslistPC124429962607280002.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0067</code>
- material：<code>/Volumes/server/Optimized Orders/pp0067/PP0067 materials.xlsx</code>

### /Volumes/server/Optimized Orders/pp0068（3 个 Excel）

- 板材清单：<code>/Volumes/server/Optimized Orders/pp0068/PP0068-Kitchen_20260729084737/Report/pp-板材清单-newPC124429962607290003.xlsx</code>
- Fittingslist：<code>/Volumes/server/Optimized Orders/pp0068/PP0068-Kitchen_20260729084737/Report/FittingslistPC124429962607290003.xlsx</code>
- 订单文件夹：<code>/Volumes/server/Optimized Orders/pp0068</code>
- material：<code>/Volumes/server/Optimized Orders/pp0068/pp0068 materials.xlsx</code>


## 第二次短暂启动说明

我在第一次退出后，为确认 App 是否已关闭而调用了会自动启动 App 的状态读取，因此 App 又短暂启动了一次：

- 10:05:58.835：读取本地索引
- 10:05:59.598–10:06:11.426：再次执行 scan-server，约11.83秒
- 没有发现第二次 sync-index 启动记录
- 随后已退出 App，最终进程状态：com.pacificpride.traveler-assistant isRunning=false

完整后端日志：[operation-log.jsonl](/Users/lantian/Documents/工作流程助手/data/operation-log.jsonl)

