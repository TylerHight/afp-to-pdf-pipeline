flowchart LR
    %% Shape conventions:
    %% [Rectangle] = compute / service
    %% [/Parallelogram/] = file storage / bucket
    %% {(Diamond)} = decision / validation
    %% ((Circle)) = event / trigger
    %% [(Database)] = BigQuery table / reporting store

    A[(BigQuery<br/>work_locks)]
    B[Worker Daemon]
    C{Claimed chunk?}
    D[Wait and Retry]

    E[/GCS Manifest Bucket<br/>Chunk JSON/]
    F{Manifest valid?}
    G[Fail lock and log]

    H[/GCS Input Bucket<br/>Source tar files/]
    I{Tar and AFP entries valid?}
    J[Fail chunk inputs]

    K[Invoke Converter]
    L{PDF valid?}
    M[Record failure result]

    N[Routing Rules Config]
    O[/GCS Output Buckets<br/>PDF outputs/]
    P[(BigQuery<br/>conversion_results)]
    Q[Complete lock row]

    A -->|available chunk rows| B
    B --> C
    C -- No --> D --> B
    C -- Yes --> E
    E --> F
    F -- No --> G --> A

    F -- Yes --> H
    H --> I
    I -- No --> J --> P --> G
    I -- Yes --> K --> L

    N --> K
    L -- No --> M --> P --> G
    L -- Yes --> O --> P --> Q --> A
