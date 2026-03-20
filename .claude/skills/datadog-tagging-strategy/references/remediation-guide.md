# Tagging Remediation Guide

## Infrastructure (Hosts)

### Add env/team tags via datadog.yaml

```yaml
tags:
  - env:prod
  - team:platform
  - tier:1
```

### Cloud tags (AWS/Azure/GCP)

Tag EC2 instances, VMs, etc. at the cloud level -- Datadog inherits these automatically.

## APM Services (Unified Service Tagging)

### Environment variables (recommended)

```bash
export DD_ENV=prod
export DD_SERVICE=store-backend
export DD_VERSION=v2.1.3
```

### Tracer initialization

```javascript
tracer.init({
  env: 'prod',
  service: 'store-backend',
  version: 'v2.1.3'
})
```

## Monitors

Add tags in Datadog UI or via API:
- `team:backend-team` -- for routing with notification rules
- `priority:p1` -- for severity classification (P1-P5)
- `service:store-backend` -- for correlation

## Logs

### Log collection config

```yaml
logs:
  - type: file
    path: /var/log/app.log
    service: store-backend
    source: python
    tags:
      - env:prod
      - team:backend-team
```

## Automation Recommendations

### Tag Policy as Code

```yaml
# tagging-policy.yaml
required_tags:
  hosts: [env, team]
  services: [service, env, version]
  monitors: [service, team, priority]
allowed_values:
  env: [dev, stage, prod]
  tier: [1, 2, 3, 4]
  priority: [p1, p2, p3, p4, p5]
```

### CI/CD Tag Validation

```bash
if [ -z "$DD_ENV" ] || [ -z "$DD_SERVICE" ] || [ -z "$DD_VERSION" ]; then
  echo "Error: UST tags required for deployment"
  exit 1
fi
```

### Regular Audits

Schedule weekly tagging audits and monthly compliance reports using this skill.
