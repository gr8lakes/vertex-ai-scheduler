# Vertex AI API 自动化启停方案（Serverless 方案）

## 1. 背景与目标
目前测试环境中的 Vertex AI (`aiplatform.googleapis.com`) 在夜间闲置期间依然可能会产生不必要的消耗，我们需要在夜间停止该服务，并在白天恢复。
当前方案采用固定时间触发，通过 Cloud Scheduler 在指定时间调用 Cloud Workflows，完成 Vertex AI API 的启停。

- **关闭时间：** 每天晚上 `19:00`
- **开启时间：** 每天早上 `10:00`

## 2. 方案选型与架构设计
经过验证，最终选定 **Cloud Scheduler + Cloud Workflows** 方案。此方案为 GCP 纯原生 (Serverless) 架构，无需挂载虚拟机实例或容器服务，做到**零运维、零空闲计算成本**。

### 2.1 架构流程
1. **Cloud Scheduler (定时任务)：** 以标准的 Unix Cron 格式在每天定点（例如 `19:00`）发出触发请求给工作流实例。
2. **Cloud Workflows (编排引擎)：**
   - 接收到触发参数 (`action: enable` 或 `action: disable`)。
   - 使用 OAuth2 认证机制调用 GCP 原生 **Service Usage API**（`serviceusage.googleapis.com`）执行 `enable` 或 `disable`。

### 2.2 架构优势
* **纯 Serverless：** 无需维护 Linux crontab 或 Docker 容器。
* **低成本/免费：** Workflows 的执行次数在免费额度内。
* **安全性高：** 直接利用服务账号 (Service Account) 及 OAuth2，避免代码中硬编码任何凭证或者 Token。

## 3. 具体部署配置步骤

### 3.1 权限筹备 (IAM 配置)
在 IAM 及管理中创建一个专用的 Service Account（服务使用账号），比如 `vertex-scheduler-sa`。需要授予该账号以下**两项核心权限**：
1. **服务使用量管理员 (Service Usage Admin / `roles/serviceusage.serviceUsageAdmin`)** 
   - *用途：授权 Workflow 底层通过 API 对项目层级的各项服务进行启用和禁用。*
2. **Workflows 调用方 (Workflows Invoker / `roles/workflows.invoker`)**
   - *用途：授权 Cloud Scheduler 拥有调用该 Workflow 实例的权限。*

### 3.2 部署 Cloud Workflows
在 GCP 控制台中创建一个 Workflow 实例，关联上方创建的服务账号，并使用以下 YAML 定义：

```yaml
main:
  params: [args]
  steps:
    - init:
        assign:
          - project_id: "zm-vertexai-test01"
          - service_name: "aiplatform.googleapis.com"
          - action: ${args.action} # 传入 "enable" 或 "disable"
          
    - toggleVertexAI:
        call: http.post
        args:
          url: ${"https://serviceusage.googleapis.com/v1/projects/" + project_id + "/services/" + service_name + ":" + action}
          auth:
            type: OAuth2
        result: toggleResult

    - returnResult:
        return: ${toggleResult}
```

### 3.3 配置 Cloud Scheduler 定时任务
针对 Workflow 实例，部署两个 Cloud Scheduler 触发器：

**【任务 1】晚间关闭策略**
* **触发频率：** `0 19 * * *`
* **时区：** `China Standard Time (CST)`
* **目标 (Target)：** 指向刚创建的 Workflow，并赋予对应的服务账号
* **执行参数 (Payload)：** `{"action": "disable"}`

**【任务 2】早间开启策略**
* **触发频率：** `0 10 * * *`
* **时区：** `China Standard Time (CST)`
* **目标 (Target)：** 指向刚创建的 Workflow，并赋予对应的服务账号
* **执行参数 (Payload)：** `{"action": "enable"}`

## 4. 容灾与回退策略说明
本方案已经移除外部随机数 API 依赖，Workflow 触发后会直接调用 Service Usage API 执行开关动作。
* **影响面：** 如果晚上关闭失败，会额外跑一晚上产生常规资源计费；如果早上开启失败，发现 Vertex 报错时可以到后台手动点击 enable 恢复。
* **本地化方案（备用）：** 若需要脱离 Cloud Scheduler + Cloud Workflows，可切换到团队内部现有的 Linux Crontab Bash 脚本形式 (即 `/Users/bruce.tian/Documents/01_chent/vertex-ai-scheduler/setup_cron.sh`) 维持逻辑。
