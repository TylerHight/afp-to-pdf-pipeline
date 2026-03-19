# Routing Rules Design

## Purpose

This document defines where destination routing configuration lives, the config format, what fields it keys off of, how precedence works, how changes are deployed, and what happens if no rule matches.

It exists to keep routing logic out of shell scripts and hardcoded worker branches, making destination changes safe and auditable.

## Scope

This document covers:

- where routing rules config is stored
- config file format and schema
- routing dimensions and matching logic
- precedence rules when multiple rules match
- deployment and versioning strategy
- fallback behavior when no rule matches
- validation requirements

This document does not cover:

- PDF naming conventions within a destination (that may be a separate spec)
- bucket lifecycle policies or retention rules
- IAM permissions for destination buckets

## Routing Rules Responsibilities

The routing rules config determines:

- which GCS bucket a PDF should be written to
- which prefix within that bucket
- optional metadata or tagging rules for the output object

The routing rules should not determine:

- whether a conversion happens (that is the planner's job)
- chunk membership (that is deterministic from the planner)
- retry logic (that is the worker's responsibility)

## Config Location

Recommended location:

- deployed with the worker code as a versioned file
- stored in the worker deployment directory or config directory
- loaded by the Python worker at startup

Example path:

```text
/opt/afp-pipeline/config/routing-rules.yaml
```

Alternative for v1:

- store in GCS and download at worker startup
- cache locally with a TTL or version check

Recommended v1 approach:

- deploy as a file with the worker code
- version it in the same repository as the worker
- redeploy workers when routing rules change

## Config Format

Recommended format:

- YAML for readability and operational debugging
- JSON is acceptable if the team prefers it

The config should be a list of routing rules evaluated in order.

### Example Config Structure

```yaml
version: "1"
default_bucket: "gs://afp-output-default"
default_prefix: "unmatched"

rules:
  - name: "recent-month-primary"
    priority: 100
    conditions:
      processing_month_gte: "2026-01"
      line_of_business: "residential"
    destination:
      bucket: "gs://afp-output-residential"
      prefix: "invoices/{processing_month}/{statement_date}"
    
  - name: "legacy-business-archive"
    priority: 90
    conditions:
      processing_month_lt: "2026-01"
      line_of_business: "business"
    destination:
      bucket: "gs://afp-output-business-archive"
      prefix: "legacy/{processing_month}"
    
  - name: "test-environment"
    priority: 80
    conditions:
      environment: "test"
    destination:
      bucket: "gs://afp-output-test"
      prefix: "test-runs/{processing_month}"
```

## Routing Dimensions

The routing rules should support matching on known business and operational dimensions.

### Required Dimensions

Dimensions that must be available for routing:

- `processing_month` (string, format `YYYY-MM`)
- `statement_date` (date or string, format `YYYY-MM-DD`)

### Recommended Dimensions

Dimensions that should be supported if available from source metadata or manifest:

- `line_of_business` (string, e.g., "residential", "business", "wholesale")
- `invoice_type` (string, e.g., "standard", "summary", "detail")
- `environment` (string, e.g., "prod", "test", "dev")
- `ban` (string, for special-case routing if needed)
- `source_system` (string, if multiple source systems exist)

### Optional Dimensions

Dimensions that may be added later:

- `region` or `market`
- `customer_segment`
- `billing_cycle`

## Matching Logic

### Condition Operators

Each condition should support:

- exact match: `field: "value"`
- greater than or equal: `field_gte: "value"`
- less than: `field_lt: "value"`
- in list: `field_in: ["value1", "value2"]`
- regex match: `field_regex: "pattern"` (use sparingly)

### Multi-Condition Rules

When a rule has multiple conditions, all conditions must match (AND logic).

Example:

```yaml
conditions:
  processing_month_gte: "2026-01"
  line_of_business: "residential"
```

This matches only if both conditions are true.

### OR Logic

If OR logic is needed, define separate rules with appropriate priorities.

## Precedence Rules

Rules are evaluated in priority order, highest priority first.

### Priority Assignment

Recommended priority bands:

- 100-199: current production rules
- 80-99: test or staging rules
- 60-79: legacy or archive rules
- 40-59: special-case overrides
- 1-39: catch-all or default rules

### First Match Wins

The worker should use the first rule that matches all conditions.

Once a match is found, stop evaluating further rules.

### Tie-Breaking

If two rules have the same priority, the worker should:

- log a warning
- use the first rule in document order
- surface the ambiguity to operations for review

Recommended practice:

- avoid priority ties
- assign unique priorities during config authoring

## Destination Path Templating

The destination prefix should support simple variable substitution.

Supported template variables:

- `{processing_month}`
- `{statement_date}`
- `{ban}`
- `{chunk_index}`
- `{worker_id}`

Example:

```yaml
prefix: "invoices/{processing_month}/{statement_date}"
```

Resolves to:

```text
invoices/2026-03/2026-03-15
```

### Validation

The worker should validate that:

- all template variables can be resolved
- the resolved path does not contain invalid characters
- the resolved path does not escape the intended bucket structure

## Fallback Behavior

### No Matching Rule

If no rule matches, the worker should:

- use the `default_bucket` and `default_prefix` from the config
- log a warning with the unmatched dimensions
- write a `FAILED` result row with failure code `NO_ROUTING_RULE`
- fail the conversion for that item

Alternative v1 behavior if a true default is acceptable:

- write to the default destination
- log the unmatched case
- write a `SUCCESS` result row but flag it for review

Recommended v1 approach:

- fail explicitly when no rule matches
- require operators to add a catch-all rule if a default is truly desired

### Missing Config

If the routing rules config is missing or unreadable:

- the worker should fail to start
- log a fatal error
- do not attempt to process any chunks

### Malformed Config

If the config is malformed:

- the worker should fail to start
- log the validation errors
- do not attempt to process any chunks

## Deployment Strategy

### Versioning

The routing rules config should be versioned.

Recommended approach:

- include a `version` field in the config
- record the config version in `work_locks.metadata_json` at planning time
- record the config version in `conversion_results` at conversion time

This makes it possible to:

- audit which rules were active for a given chunk
- replay with the same rules if needed
- detect config drift across workers

### Deployment Process

Recommended v1 deployment:

1. update the routing rules config in the repository
2. increment the config version
3. redeploy the worker code and config to all 12 VMs
4. restart the worker daemons
5. verify the new config is loaded by checking worker logs

### Rolling Deployment

For v1, a simple stop-and-restart deployment is acceptable.

For v2, consider:

- rolling restart with health checks
- config hot-reload without full worker restart
- canary deployment to one VM before full rollout

### Config Validation

Before deployment, validate:

- YAML/JSON syntax is correct
- all required fields are present
- priorities are unique or intentionally tied
- destination buckets exist and are writable
- template variables are valid

Recommended validation tool:

- a Python script that loads and validates the config
- run as part of CI/CD before deployment

## Example Rules For Common Scenarios

### Scenario 1: Route By Month And Line Of Business

```yaml
rules:
  - name: "residential-2026"
    priority: 100
    conditions:
      processing_month_gte: "2026-01"
      line_of_business: "residential"
    destination:
      bucket: "gs://afp-output-residential"
      prefix: "invoices/{processing_month}"
  
  - name: "business-2026"
    priority: 100
    conditions:
      processing_month_gte: "2026-01"
      line_of_business: "business"
    destination:
      bucket: "gs://afp-output-business"
      prefix: "invoices/{processing_month}"
```

### Scenario 2: Archive Older Months

```yaml
rules:
  - name: "archive-pre-2026"
    priority: 70
    conditions:
      processing_month_lt: "2026-01"
    destination:
      bucket: "gs://afp-output-archive"
      prefix: "archive/{processing_month}"
```

### Scenario 3: Test Environment Override

```yaml
rules:
  - name: "test-override"
    priority: 110
    conditions:
      environment: "test"
    destination:
      bucket: "gs://afp-output-test"
      prefix: "test/{processing_month}"
```

### Scenario 4: Catch-All Default

```yaml
rules:
  - name: "catch-all"
    priority: 1
    conditions: {}
    destination:
      bucket: "gs://afp-output-default"
      prefix: "unmatched/{processing_month}"
```

## Worker Implementation Requirements

The worker must:

- load the routing rules config at startup
- parse and validate the config before processing any chunks
- evaluate rules in priority order for each conversion unit
- resolve template variables using available metadata
- log the matched rule name and destination for each output
- fail explicitly if no rule matches and no default is configured

## Operational Observability

The routing rules should be observable through:

- worker startup logs showing config version and rule count
- per-conversion logs showing matched rule name
- `conversion_results` rows including destination URI
- periodic audits of unmatched or default-routed outputs

Recommended metrics:

- count of outputs per destination bucket
- count of unmatched routing attempts
- count of outputs using the default rule

## Change Management

### Adding A New Rule

1. add the rule to the config with appropriate priority
2. validate the config
3. deploy to all workers
4. monitor for unmatched cases

### Modifying An Existing Rule

1. update the rule conditions or destination
2. increment the config version
3. deploy to all workers
4. verify outputs are routed correctly

### Removing A Rule

1. ensure no active chunks depend on the rule
2. remove the rule from the config
3. deploy to all workers
4. monitor for unmatched cases

## Validation Rules

### Config Validation

The worker should validate at startup:

- config file exists and is readable
- config is valid YAML/JSON
- `version` field is present
- `default_bucket` is present
- `rules` is a list
- each rule has `name`, `priority`, `conditions`, and `destination`
- destination bucket URIs are valid GCS paths
- template variables in prefixes are recognized

### Runtime Validation

The worker should validate at conversion time:

- all template variables can be resolved
- the resolved destination URI is valid
- the destination bucket is writable (checked once at startup or cached)

## Failure Scenarios

### Config Load Failure

If the config cannot be loaded:

- worker fails to start
- logs the error
- does not process any chunks

### Rule Match Failure

If no rule matches:

- worker records a `FAILED` result with code `NO_ROUTING_RULE`
- logs the unmatched dimensions
- does not write output to a fallback destination unless explicitly configured

### Template Resolution Failure

If a template variable cannot be resolved:

- worker records a `FAILED` result with code `ROUTING_TEMPLATE_ERROR`
- logs the missing variable
- does not write output

## Acceptance Criteria

This design is ready for implementation when:

- the config format is defined and validated
- precedence rules are clear
- fallback behavior is explicit
- deployment process is documented
- workers can load and evaluate rules without ambiguity
- unmatched cases are handled safely

## Recommended Implementation Order

1. Define the config schema and example rules.
2. Implement config loading and validation in Python.
3. Implement rule evaluation and precedence logic.
4. Implement template variable resolution.
5. Add logging and observability.
6. Test with representative routing scenarios.
7. Document deployment and change management procedures.