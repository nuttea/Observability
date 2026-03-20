# Tagging Framework

## Reserved Tags (Must Have)

| Tag       | Scope          | Purpose                      | Target Coverage |
| --------- | -------------- | ---------------------------- | --------------- |
| `env`     | All            | Environment (dev/stage/prod) | >95%            |
| `service` | APM, Logs      | Service identification       | >90%            |
| `version` | APM            | Application version          | >80%            |
| `source`  | Logs           | Log source/technology        | >90%            |
| `host`    | Infrastructure | Hostname (auto)              | 100%            |
| `device`  | Infrastructure | Disk/network device          | 100%            |

## Recommended Tags (Should Have)

| Tag           | Priority | Purpose                 | Target Coverage |
| ------------- | -------- | ----------------------- | --------------- |
| `team`        | CRITICAL | Ownership & routing     | >85%            |
| `runtime`     | HIGH     | Framework/technology    | >75%            |
| `journey`     | HIGH     | User flow tracking      | >60%            |
| `role`        | HIGH     | Service function        | >75%            |
| `application` | HIGH     | Business application    | >80%            |
| `tier`        | MEDIUM   | Criticality (1-4)       | >70%            |
| `backup`      | MEDIUM   | Backup strategy         | >60%            |
| `platform`    | MEDIUM   | Infrastructure platform | >65%            |
| `product`     | MEDIUM   | Business product        | >60%            |
| `network`     | MEDIUM   | Network segment         | >50%            |
| `compliance`  | MEDIUM   | Regulations (PCI, GDPR) | >50%            |
| `datatype`    | MEDIUM   | Data classification     | >50%            |
| `datacenter`  | MEDIUM   | Physical location       | >60%            |

## Scoring System (Total: 100 points)

### Infrastructure (40 points)
- env tag: 20 pts (>95% = full)
- team tag: 15 pts (>85% = full)
- tier tag: 5 pts (>70% = full)

### Services (30 points)
- UST complete (service+env+version): 20 pts (>80% = full)
- team tag: 10 pts (>85% = full)

### Monitors (20 points)
- team tag: 10 pts (>90% = full)
- priority tag: 10 pts (>90% = full)

### Logs & Dashboards (10 points)
- service tag in logs: 5 pts
- Dashboard tags: 5 pts

### Health Status
- 90-100: Excellent
- 75-89: Good
- 60-74: Needs Improvement
- <60: Action Required

## Tag Best Practices

### DO
- Use lowercase: `env:prod` not `Env:Prod`
- Use consistent separators: `team-name` or `team_name` (pick one)
- Include UST for all services: service, env, version
- Add team tags for ownership and routing
- Document allowed tag values

### DON'T
- Use CamelCase: `TeamName`
- Use unbounded values: user_id, request_id, timestamp
- Mix formats: `env:prod` and `environment:production`
- Include special characters (they become underscores)

## Tag Cardinality Guidelines

- **Low** (1-20 values): Ideal -- env, tier, region
- **Medium** (20-100 values): Acceptable -- team, service
- **High** (>100 values): Avoid for tags -- use log/span attributes instead
