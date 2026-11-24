# Fermi Problems

A Fermi estimation uses prior experience and physical reasoning to arrive at a rough value for a quantity. Also called order-of-magnitude approximation, guesstimate, or back-of-the-envelope calculation.

## Strategies

### Get big lengths from smaller lengths

Break a big thing into smaller measurable things. Estimate one small thing, multiply.

Example: building height = floors _ people-per-floor-height _ person-height.

Reverse works too: estimate thickness of paper from a stack divided by page count.

### Get areas and volumes from lengths

Model complex objects as simple shapes (sphere, box). Estimate linear dimensions, apply geometric formulas.

### Get masses from volumes and densities

```
mass = density * volume
```

Reference densities:

- Air: ~1 kg/m^3
- Water: ~10^3 kg/m^3
- Dense everyday solids: up to ~10^4 kg/m^3

Check: does it float or sink in air or water?

### Bounding

When you lack intuition, set upper and lower bounds.

Example: moose mass > person (~10^2 kg), moose mass < car (~10^3 kg).

Take geometric mean of bounds: `sqrt(upper * lower)`.

Adjust toward the bound you think is more likely.

### One significant figure is fine

Order of magnitude is usually good enough. Keep arithmetic simple.

### Sanity check

Compare your answer to known quantities with the same dimensions. Check units first, then arithmetic, then logic.

## Example problems

- How many terabytes to store all written production of humanity? (Reference: 5 pages of ~500 words = 10 KB of text)
- How long to brute-force a password of x characters?
- Volume of a human body (assuming primarily water)?
- Mass of air in a classroom?
- Number of molecules in a human body? (Water molecular mass = 18 g/mol, ~10^24 atoms/mol)
- Number of molecules in Earth? (Average molecular mass = 30 g/mol)
- Surface area of a person?
- How many solar systems to tile the Milky Way disk?
- Density, diameter, and distance of the Moon (subtends ~0.5 degrees)?
- Mass of a virus?
- Maximum floating-point operations a human could perform in a lifetime? How long for a supercomputer?

## References

- <https://courses.lumenlearning.com/suny-osuniversityphysics/chapter/1-5-estimates-and-fermi-calculations/>
- <https://ram921.medium.com/answering-unanswerable-questions-fermi-problems-in-product-management-interviews-30d2806da094>
- <http://www.inference.org.uk/sanjoy/oom/>
- <https://w.astro.berkeley.edu/~echiang/oom/oom.html>
