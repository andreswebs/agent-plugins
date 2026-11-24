# Capacity Planning

Back of the envelope (BOE) calculations are estimates generated using a combination of thought experiments and performance numbers through simple arithmetic.

Uses: decide whether to partition a database, compare architectures, evaluate feasibility, identify bottlenecks, ensure high availability, improve cost efficiency, define SLOs/SLAs, predict capacity requirements.

## Scaling types

Vertical: increase CPU cores, memory, disk on a single server. Limited by saturation point.

Horizontal: add multiple machines. Increases complexity.

Diagonal: combine vertical and horizontal — upgrade components and replicate servers.

## Reference numbers

### Powers of two

| Power | Approx Value  | Bytes |
| ----- | ------------- | ----- |
| 10    | 1 thousand    | 1 KB  |
| 20    | 1 million     | 1 MB  |
| 30    | 1 billion     | 1 GB  |
| 32    |               | 4 GB  |
| 40    | 1 trillion    | 1 TB  |
| 50    | 1 quadrillion | 1 PB  |

### Data sizes

| Data Type        | Size (bytes) |
| ---------------- | ------------ |
| int              | 4            |
| float            | 8            |
| boolean          | 4            |
| UTF-8 character  | 1            |
| UTF-8 in Chinese | 3            |
| UNIX timestamp   | 4            |

### Availability numbers

| Availability | Downtime per year |
| ------------ | ----------------- |
| 99%          | 3.6 days          |
| 99.9%        | 8.6 hours         |
| 99.99%       | 52 minutes        |
| 99.999%      | 5 minutes         |
| 99.9999%     | 31 seconds        |

MTBF: mean time between failures. MTTR: mean time to repair.

### Latency numbers

| Operation                           | Time   |
| ----------------------------------- | ------ |
| L1 cache reference                  | 0.5 ns |
| Branch mispredict                   | 5 ns   |
| L2 cache reference                  | 7 ns   |
| Mutex lock/unlock                   | 25 ns  |
| Main memory reference               | 100 ns |
| Compress 1K bytes with Zippy        | 10 us  |
| Send 1 KB bytes over 1 Gbps network | 10 us  |
| Read 4 KB randomly from SSD         | 150 us |
| Read 1 MB sequentially from memory  | 250 us |
| Round trip within same datacenter   | 500 us |
| Read 1 MB sequentially from SSD     | 1 ms   |
| HDD seek                            | 10 ms  |
| Read 1 MB sequentially from 1 Gbps  | 10 ms  |
| Read 1 MB sequentially from HDD     | 30 ms  |
| Send packet CA->Netherlands->CA     | 150 ms |

Time conversions: 1 ns = 10^(-9) s, 1 us = 10^(-6) s, 1 ms = 10^(-3) s.

Days to seconds shortcut: multiply by 10^(-5).

Key insights:

- Memory is fast, disks are slow
- Compression saves network bandwidth
- Writes are ~40x more expensive than reads
- Globally shared data is expensive (lock contention serializes transactions)
- ~7 inter-region round trips per second possible
- ~2000 intra-datacenter round trips per second possible

## BOE tactics

- Round numbers (83 → 100)
- Label units
- Convert to operations per second (1M requests/day = 12 requests/second)
- State assumptions explicitly
- Use magnitude abbreviations (1000 = 1K)
- Use real data when available, estimate when not

## Estimation formulas

### QPS (queries per second)

```
QPS = number_of_CPU_cores / avg_CPU_time_per_request_seconds
```

From user activity:

```
QPS = DAU * tx_per_session * 10^(-5)
```

Example: 1K users, 15 req/day each = 15K req/day ≈ 0.15 QPS.

Peak traffic estimation:

- 10% per hour rule: assume 10% of daily traffic in 1 hour
- Or: peak = 2 \* average

### Latency estimation

Sequential: latency = sum of all resource latencies.

Parallel: latency = max of all resource latencies.

Target: < 250 ms for real-time experience.

### Bandwidth estimation

```
bandwidth = size_per_transfer_KB * transfers_per_day
```

Calculate separately for ingress (client requests) and egress (server responses).

## Useful metrics

System: CPU %, RAM bytes, disk usage bytes, disk I/O, network throughput bytes/sec.

Application: QPS (queries/sec), RPS (requests/sec), TPS (transactions/sec).

## Real-world capacity planning

Ceiling: highest metric value before SLO degradation.

```
limit = ceiling * safety_factor
```

Example: safe CPU ceiling = 1.0 \* 0.85 = 0.85.

Steps:

1. Correlate system and application metrics
2. Find ceilings from historical data
3. Establish safe limits with high/low watermarks for alerting

Performance testing:

1. Set up test environment
2. Determine single-host load patterns
3. Run test scripts mimicking production
4. Analyze results: find ceilings, understand bottlenecks

## Graceful degradation

When capacity limits are exceeded:

- Disable heavy-load features
- Cache dynamic content as static
- Serve stale content

## Database capacity concepts

- Working Set Size: dataset needed during normal operation
- Average Transaction Size: working dataset of a single transaction
- Request Rate: expected throughput
- Update Rate: how often data changes
- Consistency Rate: time for updates to propagate
- Locality: how data is organized physically
- Computation: math operations over data
- Latency: expected transaction response time

## References

- <https://colin-scott.github.io/personal_website/research/interactive_latency.html>
- <https://systemdesign.one/back-of-the-envelope>
- <https://github.com/donnemartin/system-design-primer#back-of-the-envelope-calculations>
- Jeff Dean, "Building Software Systems At Google" (2010), Stanford
