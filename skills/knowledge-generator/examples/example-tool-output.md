# 示例：项目工具类知识库文件输出

以下是一个典型的项目工具类知识库文件的输出示例，展示使用 knowledge-generator skill 生成的最终文件样式。

---

# 分布式锁组件（DistributedLock）

## 背景

充电计费平台在并发账单创建、并发退款等场景下存在数据竞争风险（如同一协议被并发触发生成重复账单）。项目基于 Redis 封装了一套通用分布式锁组件，统一管理锁的获取、续期与释放，避免各业务线自行实现导致锁逻辑不一致。

## 使用说明

- 锁 Key 必须以 `charge:lock:` 为前缀，后接业务维度（如 `charge:lock:bill:{protocolNo}`）
- 默认租约时长 30 秒，可透传自定义时长（单位：毫秒）
- 默认开启看门狗自动续期，续期间隔为租约时长的 1/3
- 禁止在事务内使用分布式锁（锁释放早于事务提交会引发并发问题）
- 获取锁失败的默认行为是抛出 `LockAcquireException`，需要重试的业务需显式指定重试策略

## 关键代码

| 逻辑 | 文件 |
| --- | --- |
| 锁抽象与注解定义 | com.example.charge.common.lock.DistributedLock |
| Redis 实现（Lua 加锁脚本） | com.example.charge.common.lock.RedisLockTemplate |
| 看门狗续期 | com.example.charge.common.lock.WatchdogRenewer |
| 锁失败重试策略 | com.example.charge.common.lock.LockRetryPolicy |

## 排查建议

1. 先确认锁 Key 是否拼接正确（排查 `charge:lock:` 前缀与业务参数）
2. 检查 Redis 是否存在残留 Key（未正常释放会导致后续请求持续获取失败）
3. 查看是否在事务内加锁（`@Transactional` 与 `@DistributedLock` 同时出现需排查）
4. 查日志：`RedisLockTemplate` 在加锁成功、续期、释放处均有 log.info 输出

## 待补充

- 锁监控看板的指标定义
- 不同业务线的锁租约时长最佳实践
