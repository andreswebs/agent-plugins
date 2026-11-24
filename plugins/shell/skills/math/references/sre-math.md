# Math for SREs

## Percentiles vs averages

Averages hide slow requests. Always use percentiles.

- p50 (median): what the middle request experienced
- p95: where performance starts degrading (5% of requests worse)
- p99: the tail — slowest 1%

Example: 1000 requests at 100 ms + 50 requests at 2-5 seconds → average ~200 ms looks fine, but 50 users had a broken experience.

At scale (thousands of req/sec), even 1% means thousands of affected users per minute.

## Little's Law

```
L = λ × W
```

- L = concurrent requests in the system
- λ = arrival rate (req/sec)
- W = average latency (seconds)

Analogy: 10 customers/min arriving at a coffee shop, each stays 5 min → ~50 people inside at any time.

As arrival rate approaches capacity, latency grows sharply. Design for 60-70% utilization in steady state.

## Error budgets

| SLO     | Monthly downtime |
| ------- | ---------------- |
| 99.9%   | ~43 minutes      |
| 99.99%  | ~4 minutes       |
| 99.999% | ~26 seconds      |

Error budgets connect engineering and business. They determine when it is safe to release fast and when to slow down.

If you burn 1 hour of downtime in a 99.9% system, the month's budget is gone.

## Queueing theory

Queues form when demand approaches capacity. Growth is not linear — it is explosive.

- 50% utilization: requests pass smoothly
- 80% utilization: queues start to show
- 90% utilization: small bursts cause massive delays

Waiting time soars near 100% utilization. This is why "90% CPU" should make you nervous, not efficient.

Run with headroom instead of chasing high utilization.

## Graph literacy

When reading monitoring graphs:

1. What does the metric mean?
2. What is the time window and scale?
3. Compare across related metrics (CPU flat but latency rising → check queue length)
4. Do metrics match user experience?

Common mistakes:

- Averages instead of percentiles
- Sampling window too wide (1-min average smooths 5-sec spikes)
- Axis scale: log scale compresses big spikes into small bumps
- Heatmaps: if density is at the top, it signals trouble

## On-call scenario walkthrough

Pager fires, users can't check out, average latency is flat at 200 ms.

1. Check percentiles: p95 = 2s, p99 = 5s → tail is hot
2. Check throughput: 180 req/sec near 200 req/sec capacity → queues forming
3. Calculate error budget impact: 1 hour of this = 60 min > monthly allowance for 99.9% SLO
4. Check queue depth: climbing, confirms high utilization as root cause

Actions:

- Slow down releases (budget nearly gone)
- Add temporary capacity
- Post-incident: show percentiles, throughput vs latency curve, queueing math

## References

- <https://one2n.io/blog/sre-math-every-engineer-should-know-a-practical-guide>
