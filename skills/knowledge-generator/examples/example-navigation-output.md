# 示例：项目导航类知识库文件输出

以下是一个典型的项目导航类知识库文件的输出示例，展示使用 knowledge-generator skill 生成的最终文件样式。

---

# 充电计费平台整体导航

## 概述

充电计费平台是一个面向充电桩运营商的 SaaS 收费系统，采用 Java 多模块 Maven 工程构建。核心职责包括：充电订单管理、计费策略配置、账单生成与结算、退款与冲正、商户与协议管理。系统对外提供 HTTP 接口与 Dubbo 服务两种接入方式。

## 根模块

| 模块 | 职责 | 源码目录 |
| --- | --- | --- |
| charge-web | Web 入口层，提供 HTTP 接口与参数校验 | charge-web/src/main/java/com/example/charge/controller |
| charge-service | 核心业务层，承载主要业务编排逻辑 | charge-service/src/main/java/com/example/charge |
| charge-dal | 数据访问层，封装持久化 | charge-dal/src/main/java/com/example/charge/dao |
| charge-integration | 外部集成层，对接支付通道与消息推送 | charge-integration/src/main/java/com/example/charge/integration |
| charge-common | 公共组件，枚举、常量、工具类 | charge-common/src/main/java/com/example/charge/common |

## 核心目录

- 计费核心：`charge-service/.../charge/billing/` — 计费策略匹配与金额计算
- 账单核心：`charge-service/.../charge/bill/` — 账单全生命周期管理
- 退款冲正：`charge-service/.../charge/refund/` — 退款与冲正流程
- 商户协议：`charge-service/.../charge/merchant/` — 商户与计费协议管理

## 问题定位

| 问题类型 | 定位模块 | 关键类 |
| --- | --- | --- |
| 账单金额不对 | billing | ChargeCalculator / StrategyMatcher |
| 账单状态卡住 | bill | BillManager / BillStatusEnum |
| 退款失败 | refund | RefundManager / RefundResultEnum |
| 支付回调没到账 | integration | PayCallbackHandler |

## 待补充

- 各模块的详细启动依赖关系
- 配置中心关键配置项说明
- 定时任务清单与触发规则
