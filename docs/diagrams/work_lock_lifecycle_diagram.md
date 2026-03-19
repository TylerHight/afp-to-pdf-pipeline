flowchart LR
    %% Shape conventions:
    %% [Rectangle] = compute / service
    %% [/Parallelogram/] = file storage / bucket
    %% {(Diamond)} = decision / validation
    %% ((Circle)) = event / trigger
    %% [(Database)] = BigQuery table / reporting store

    A[Planning Job]
    B[/GCS Manifest Bucket<br/>Chunk definition JSON/]
    C[(BigQuery<br/>work_locks)]

    D[Worker Daemon<br/>12 Linux VMs]
    E{Lease acquired?}
    F[Wait + Retry]

    G[Download Chunk Inputs<br/>Manifest + tar]
    H[Process Chunk<br/>Extract/filter AFP<br/>Convert to PDF]
    I{Conversion valid?}

    J[/GCS Output Buckets<br/>PDF outputs/]
    K[(BigQuery<br/>conversion_results)]
    L[Complete Lock Row<br/>Status = DONE]
    M[Fail Lock Row<br/>Status = FAILED]

    N{Heartbeat lost?}
    O[Lease expires]
    P[Chunk becomes available again]

    Q[Reporting Views<br/>Success / Failure / Remaining]
    R[Routing Rules Config]

    A -->|write chunk JSON| B
    A -->|insert one row per chunk| C

    C -->|available chunk rows| D
    D -->|claim, heartbeat, complete, fail| C
    D --> E
    E -- No --> F --> D
    E -- Yes --> G --> H

    R --> H
    H --> I
    I -- Yes --> J --> K --> L --> C
    I -- No --> K --> M --> C

    D -. worker crash or missed heartbeat .-> N
    N -- Yes --> O --> P --> C

    K --> Q
