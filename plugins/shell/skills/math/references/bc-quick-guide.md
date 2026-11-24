# bc — Arbitrary-Precision Calculator

## Basic Usage

```bash
echo "10 + 3" | bc       # 13
echo "2 ^ 32" | bc        # 4294967296
```

## Floating-Point with `scale`

By default, `bc` does **integer division**. Set `scale` to get decimal places:

```bash
echo "10 / 3" | bc              # 3  (integer!)
echo "scale=2; 10 / 3" | bc    # 3.33
echo "scale=10; 10 / 3" | bc   # 3.3333333333
```

`scale` sets the number of digits after the decimal point for division.

## Using Shell Variables

```bash
x=10
y=3
echo "scale=2; $x / $y" | bc   # 3.33
```

For untrusted input, validate first to avoid injection.

## The `-l` Flag (Math Library)

Loads the standard math library — sets `scale=20` and enables functions:

```bash
echo "s(1)" | bc -l        # 0.84147... (sine of 1 radian)
echo "c(0)" | bc -l        # 1.00000... (cosine of 0)
echo "l(2.718)" | bc -l    # 0.99993... (natural log)
echo "e(1)" | bc -l        # 2.71828... (e^1)
echo "a(1) * 4" | bc -l    # 3.14159... (π via arctan)
echo "sqrt(2)" | bc -l     # 1.41421...
```

| Function  | Meaning     |
| --------- | ----------- |
| `s(x)`    | sine        |
| `c(x)`    | cosine      |
| `a(x)`    | arctangent  |
| `l(x)`    | natural log |
| `e(x)`    | e^x         |
| `sqrt(x)` | square root |

## Here-String (Cleaner Syntax)

```bash
bc <<< "scale=4; 22 / 7"    # 3.1428
```

Avoids the `echo |` pipe.

## Multi-Line Expressions

```bash
bc -l <<< "
scale=6
x = 3.5
y = 2.1
x * y + sqrt(x)
"
# 9.220680
```

## Capturing the Result

```bash
result=$(bc <<< "scale=2; 100 / 7")
echo "${result}"   # 14.28
```

## Operators

| Operator          | Meaning             |
| ----------------- | ------------------- |
| `+ - * / %`       | Basic math          |
| `^`               | Exponentiation      |
| `== != < > <= >=` | Comparison (0 or 1) |
| `&& \|\|`         | Logical AND/OR      |

## Arbitrary Precision — bc's Superpower

```bash
echo "scale=50; 1 / 7" | bc
# .14285714285714285714285714285714285714285714285714
```
