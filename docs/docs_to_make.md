**Completed Docs**
1. ✅ **Worker Processing Design** - [`worker-processing.md`](worker-processing.md)
   - what the worker does after it claims a chunk
   - download tar
   - read manifest
   - extract/filter AFP
   - invoke converter
   - validate PDF
   - upload output
   - write `conversion_results`
   - complete/fail lock

2. ✅ **Routing Rules Design** - [`routing-rules.md`](routing-rules.md)
   - where destination routing config lives
   - config format
   - what fields it keys off of
   - how precedence works
   - how changes are deployed
   - what happens if no rule matches

3. ✅ **BigQuery Schema Spec** - [`bigquery-schema.md`](bigquery-schema.md)
   - exact schemas for:
     - `work_locks`
     - `conversion_results`
     - reporting views
   - field meanings
   - required vs nullable
   - example rows

4. ✅ **Runbook / Operations Guide** - [`runbook.md`](runbook.md)
   - how to start/stop workers
   - how to requeue failed chunks
   - how to inspect progress
   - how to handle stale leases
   - how to replay a month
   - what logs to check first

5. ✅ **Failure Handling / Recovery Guide** - [`failure-handling.md`](failure-handling.md)
   - VM crash
   - bad tar
   - corrupt AFP
   - upload failure
   - repeated chunk failure
   - stale lease recovery

6. ✅ **Deployment / Environment Setup** - [`deployment-guide.md`](deployment-guide.md)
   - VM setup
   - service accounts
   - credentials
   - Python dependencies
   - converter installation
   - `systemd` service setup
   - Terraform apply order

7. ✅ **Testing Strategy** - [`testing-strategy.md`](testing-strategy.md)
   - unit tests
   - integration tests
   - local smoke tests
   - one-month rehearsal test
   - failure injection tests
   - acceptance criteria for "ready for prod"

**All Priority Docs Complete!**

**Completed Diagrams**
1. ✅ **Worker Processing Flow** - [`diagrams/worker_processing_diagram.md`](diagrams/worker_processing_diagram.md)
   - claim chunk
   - download manifest
   - download tar
   - extract/filter AFP
   - convert
   - validate
   - upload
   - write results
   - complete/fail lock

2. ✅ **Planner / Chunking Flow** - [`diagrams/planner_chunking_diagram.md`](diagrams/planner_chunking_diagram.md)
   - scan source month
   - build inventory
   - sort deterministically
   - split into chunks
   - write manifest JSON
   - seed `work_locks`

3. ✅ **Failure / Retry Flow** - [`diagrams/failure_retry_diagram.md`](diagrams/failure_retry_diagram.md)
   - worker crash
   - missed heartbeat
   - lease expiry
   - reclaim
   - retry
   - complete/fail paths

4. ✅ **Reporting / Progress Flow** - [`diagrams/reporting_progress_diagram.md`](diagrams/reporting_progress_diagram.md)
   - `work_locks`
   - manifests
   - `conversion_results`
   - views
   - dashboards/reports
   - how "remaining" is calculated

5. ✅ **Deployment / Runtime Topology** - [`diagrams/deployment_topology_diagram.md`](diagrams/deployment_topology_diagram.md)
   - buckets
   - BigQuery dataset
   - 12 VMs
   - controller/planner runtime
   - service accounts / IAM boundaries

**Best next diagrams**

**Completed Priority Items**
✅ Docs:
1. `worker-processing.md` - DONE
2. `routing-rules.md` - DONE
3. `bigquery-schema.md` - DONE

✅ Diagrams:
1. `worker_processing_diagram.md` - DONE
2. `planner_chunking_diagram.md` - DONE
3. `failure_retry_diagram.md` - DONE

**All Completed Items**

✅ **Priority Docs (7 total)**:
1. `worker-processing.md` - DONE
2. `routing-rules.md` - DONE
3. `bigquery-schema.md` - DONE
4. `runbook.md` - DONE
5. `failure-handling.md` - DONE
6. `deployment-guide.md` - DONE
7. `testing-strategy.md` - DONE

✅ **Priority Diagrams (5 total)**:
1. `worker_processing_diagram.md` - DONE
2. `planner_chunking_diagram.md` - DONE
3. `failure_retry_diagram.md` - DONE
4. `reporting_progress_diagram.md` - DONE
5. `deployment_topology_diagram.md` - DONE

**Documentation Status: COMPLETE**

All essential documentation for building, deploying, operating, and testing the AFP-to-PDF pipeline has been created. The team now has:

- Clear architecture and design documents
- Detailed operational runbooks
- Comprehensive failure handling procedures
- Step-by-step deployment guides
- Complete testing strategies
- Visual diagrams for all major flows
- Exact BigQuery schemas and routing rules

**Next Steps for the Team**:
1. Review all documentation for accuracy
2. Begin implementation following the architecture
3. Set up test environment per deployment guide
4. Implement unit tests per testing strategy
5. Run one-month rehearsal test before production

**What not to over-document yet**
- deep UML
- sequence diagrams for every micro-case
- exhaustive API docs if there is no API yet
- governance-heavy docs no one will use during build

You want docs that help you:
- build faster
- avoid ambiguity
- recover from problems
- onboard another engineer quickly