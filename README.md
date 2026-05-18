# Agent Platform Scheduler

Automated Agent Platform API enable/disable scheduler.

This repository provides two ways to reduce idle Agent Platform usage in a test
environment:

- **Recommended:** Google Cloud Scheduler + Cloud Workflows serverless setup.
- **Fallback:** Local crontab + Bash scripts.

The default Cloud Scheduler schedule is:

- Disable Agent Platform at **19:00**.
- Enable Agent Platform at **10:00**.

## Repository Contents

| File | Purpose |
| --- | --- |
| `workflow.yaml` | Cloud Workflows definition for enabling or disabling Agent Platform. |
| `setup_cron.sh` | Installs, removes, and checks local crontab jobs. |
| `vertex_ai_toggle.sh` | Local Bash implementation that calls `gcloud services enable/disable`. |
| `Vertex_AI_自动化休眠方案宣贯文档.md` | Detailed Chinese design and rollout document. |

## Serverless Deployment

The recommended architecture is fully managed by Google Cloud:

1. **Cloud Scheduler** triggers the workflow at fixed cron times.
2. **Cloud Workflows** calls the Service Usage API to enable or disable
   `aiplatform.googleapis.com`.

### Required IAM Roles

Create or choose a service account, then grant it:

- `roles/serviceusage.serviceUsageAdmin`
- `roles/workflows.invoker`

### Deploy Workflow

Update `project_id` in `workflow.yaml`, then deploy it:

```bash
gcloud workflows deploy agent-platform-scheduler \
  --source=workflow.yaml \
  --location=asia-east1 \
  --service-account=YOUR_SERVICE_ACCOUNT_EMAIL
```

### Create Scheduler Jobs

Create one job to disable Agent Platform in the evening:

```bash
gcloud scheduler jobs create http agent-platform-disable \
  --schedule="0 19 * * *" \
  --time-zone="Asia/Shanghai" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/YOUR_PROJECT_ID/locations/asia-east1/workflows/agent-platform-scheduler/executions" \
  --http-method=POST \
  --oauth-service-account-email=YOUR_SERVICE_ACCOUNT_EMAIL \
  --headers="Content-Type=application/json" \
  --message-body='{"argument":"{\"action\":\"disable\"}"}'
```

Create another job to enable Agent Platform in the morning:

```bash
gcloud scheduler jobs create http agent-platform-enable \
  --schedule="0 10 * * *" \
  --time-zone="Asia/Shanghai" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/YOUR_PROJECT_ID/locations/asia-east1/workflows/agent-platform-scheduler/executions" \
  --http-method=POST \
  --oauth-service-account-email=YOUR_SERVICE_ACCOUNT_EMAIL \
  --headers="Content-Type=application/json" \
  --message-body='{"argument":"{\"action\":\"enable\"}"}'
```

Replace `YOUR_PROJECT_ID`, `YOUR_SERVICE_ACCOUNT_EMAIL`, and region values with
your actual environment.

## Local Crontab Fallback

The local fallback requires:

- Google Cloud SDK (`gcloud`)
- Local authentication with permission to manage services
- A configured project ID

Set the target project:

```bash
export AGENT_PLATFORM_PROJECT_ID=YOUR_PROJECT_ID
```

Install local cron jobs:

```bash
chmod +x setup_cron.sh vertex_ai_toggle.sh
./setup_cron.sh install
```

Check status:

```bash
./setup_cron.sh status
```

Remove cron jobs:

```bash
./setup_cron.sh uninstall
```

Logs are written to:

```text
logs/agent_platform_toggle.log
```

## Notes

- The workflow targets the Agent Platform service API, `aiplatform.googleapis.com`.
- The Cloud Workflows path does not depend on an external random number API.
- Do not commit service account keys or other credentials into this repository.
