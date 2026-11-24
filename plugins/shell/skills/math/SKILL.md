---
name: math
description: >
  Perform calculations, estimations, and quantitative reasoning for engineering
  and operations. Covers calculations with bc, back-of-the-envelope
  capacity planning, Fermi estimation techniques, and SRE math (percentiles,
  Little's Law, error budgets, queueing theory). Use when the user needs to
  calculate, estimate, size, or reason quantitatively about systems, infrastructure,
  latency, throughput, availability, or resource requirements — even if they don't
  explicitly mention "math" or "estimation".
---

# Math

Always use `bc` for calculations — not mental math, not shell arithmetic. For order-of-magnitude approximations, compute with `bc` first, then discard non-significant parts from the result. Use estimation techniques for capacity planning, sizing, and system design.

## Arithmetic with bc

Use `bc` for all calculations. By default `bc` does integer division. Set `scale` to control decimal places:

```bash
echo "10 / 3" | bc                    # 3 (integer division)
echo "scale=2; 10 / 3" | bc           # 3.33
echo "scale=4; 22 / 7" | bc           # 3.1428
echo "scale=10; 10 / 3" | bc          # 3.3333333333
echo "2 ^ 64" | bc                    # large integer
result=$(bc <<< "scale=2; 100 / 7")   # capture result
```

The `-l` flag loads the math library and sets scale=20. Use it for functions (sine, cosine, log, exp, sqrt):

```bash
echo "sqrt(2)" | bc -l
echo "a(1) * 4" | bc -l     # pi via arctan
echo "l(100)" | bc -l       # natural log
```

For shell variables:

```bash
x=10; y=3
echo "scale=2; $x / $y" | bc
```

See [references/bc-quick-guide.md](references/bc-quick-guide.md) for the full operator and function reference.

## Capacity planning

Back-of-the-envelope calculations for system design and sizing.

### Quick conversions

- 1M requests/day ≈ 12 requests/second
- Days to seconds: multiply by 10^(-5)
- 1 KB = 2^10, 1 MB = 2^20, 1 GB = 2^30, 1 TB = 2^40

### QPS from user activity

```
QPS = DAU * transactions_per_session * 10^(-5)
```

Peak traffic: 2x average, or assume 10% of daily traffic in 1 hour.

### Key latency references

- Memory reference: 100 ns
- SSD random read 4KB: 150 us
- Datacenter round trip: 500 us
- SSD sequential 1MB: 1 ms
- HDD seek: 10 ms
- Cross-continent packet: 150 ms

### Availability

- 99.9% = 8.6 hours downtime/year
- 99.99% = 52 minutes/year
- 99.999% = 5 minutes/year

See [references/capacity-planning.md](references/capacity-planning.md) for full reference tables, formulas, and database capacity concepts.

## Fermi estimation

Order-of-magnitude estimation using physical reasoning.

### Core strategies

1. Break big things into smaller measurable things, estimate one, multiply
2. Model complex shapes as simple geometry (sphere, box)
3. Use mass = density × volume (air ~1, water ~10^3, dense solids ~10^4 kg/m^3)
4. When uncertain, bound it: set upper and lower limits, take geometric mean
5. One significant figure is enough
6. Sanity-check: does the answer make sense compared to known quantities?

### Tactics

- Round aggressively (83 → 100)
- Label units throughout
- State assumptions explicitly
- Use magnitude abbreviations (1K, 1M, 1B)

See [references/fermi-problems.md](references/fermi-problems.md) for detailed strategies and example problems.

## SRE math

### Percentiles over averages

Averages hide the tail. Use p50, p95, p99.

At scale, 1% of requests = thousands of affected users per minute.

### Little's Law

```
L = λ × W
```

L = concurrent requests, λ = arrival rate (req/sec), W = average latency (sec).

Design for 60-70% utilization. Latency grows sharply as arrival rate approaches capacity.

### Queueing

- 50% util: smooth
- 80% util: queues appear
- 90% util: small bursts cause massive delays
- Near 100%: system collapse

### Error budgets

99.9% SLO = ~43 min downtime/month. 1 hour outage = budget gone.

Error budgets decide when to release fast vs slow down.

See [references/sre-math.md](references/sre-math.md) for detailed explanations, graph literacy tips, and on-call scenario walkthrough.
