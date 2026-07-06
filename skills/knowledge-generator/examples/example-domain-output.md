# 示例：业务领域类知识库文件输出

以下是一个典型的业务领域类知识库文件的输出示例，展示使用 knowledge-generator skill 生成的最终文件样式。

---

# 账单全生命周期

## 是什么

描述平台收费账单从创建到终态的完整状态流转链路，覆盖创建、计费、出账、支付、退款、冲正等核心子场景。当遇到账单状态异常、账单金额不一致、账单流转卡住等问题时，优先查阅本知识库。

## 核心文件

| 类型 | 文件 |
| --- | --- |
| Web 入口 | com.example.charge.controller.BillController |
| 服务接口 | com.example.charge.service.BillService |
| 服务实现 | com.example.charge.service.impl.BillServiceImpl |
| 业务编排 | com.example.charge.manager.BillManager |
| 数据对象 | com.example.charge.dao.dataobject.ChargeBillDO |
| 枚举 | com.example.charge.enums.BillStatusEnum / BillOperateTypeEnum |

## 账单创建链路

- 入口：BillFacade.syncBill()（Dubbo 接口）/ BillController.createBill()（HTTP 接口）
- 关键逻辑：BillManager.createBill() → 策略匹配 StrategyMatcher → 计费执行 ChargeCalculator → 状态初始化 BillStatusEnum.INIT
- 注意点：SimpleBill 与 ChargeBill 创建逻辑分支不同；创建时需校验协议有效期和策略配置完整性

## 账单状态流转

- INIT → CHARGED（计费完成）→ SETTLED（出账完成）→ PAID（支付完成）
- 退款分支：PAID → REFUNDING → REFUNDED
- 冲正分支：PAID → REVERSING → REVERSED
- 注意点：状态流转依赖 BillOperateTypeEnum 的操作类型枚举，非合法操作类型会被拦截

## 排查建议

1. 先确认账单当前状态（查 ChargeBillDO.chargeStatus）
2. 根据 BillStatusEnum 判断预期下一步状态
3. 检查是否有阻塞操作（如支付回调未到达、退款审核未通过）
4. 查日志：BillManager 中关键状态变更点均有 log.info 输出
5. 查枚举：BillOperateTypeEnum 是否与实际操作一致
6. 查策略：策略配置是否有效（ChargeStrategy 表）
7. 查金额：计费结果与账单金额是否一致（ChargeCalculator 输出 vs ChargeBillDO.chargeAmount）

## 高风险点

- 重复创建：syncBill 接口需幂等校验，否则同一协议可能生成重复账单
- 状态跳跃：禁止跨状态直接流转（如 INIT 直接到 PAID），需经过中间状态
- 金额精度：计费计算使用 BigDecimal，禁止使用 double 避免精度丢失
- 并发退款：同一账单并发退款请求需通过分布式锁控制

## 待补充

- 账单逾期处罚链路
- 账单合并逻辑
- 账单短信通知人选择逻辑
