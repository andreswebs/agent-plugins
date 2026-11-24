# Design template

The skeleton below is prescribed, as in a Kiro spec design document. Fill it;
do not invent the structure per feature. Seven sections are mandated and
appear in this order: Overview, Architecture, Components and Interfaces, Data
Models, Correctness Properties (when the gate passes), Error Handling, Testing
Strategy. Performance Considerations, Security Considerations and Dependencies
are added only when the requirements raise the concern. Open Questions and
Assumptions closes the document.

## Skeleton

```markdown
# Technical Design: [Feature Name]

## Overview

[2 to 3 paragraphs: the feature, its purpose, the high-level approach]

### Design goals

- [Goal, phrased as something the architecture optimises for]

### Key design decisions

- **[Decision]**: [What was chosen and why; the alternative rejected, when
  one was weighed]

## Architecture

[Overall architecture, with a Mermaid diagram of the components and the
data flow between them. Add a sequence diagram for the main request
lifecycle when there is more than one hop.]

## Components and Interfaces

### [Component_Name from the glossary]

**Purpose**: [What this component does]

**Interface**:

[interface block in the settled notation]

**Responsibilities**:

- [Responsibility]

## Data Models

### [Record_Name from the glossary]

[type or schema block in the settled notation]

**Validation Rules**:

- [Rule]

## Correctness Properties

[Only when the gate passes; see below]

### Property 1: [Short name]

_For all_ [quantified inputs], [the behaviour that must hold].

**Validates: Requirements 1.1, 1.2**

## Error Handling

### [Error scenario]

**Condition**: [When this error occurs]
**Response**: [How the system handles it]
**Recovery**: [How the system recovers]

## Testing Strategy

### Property-based testing

**Property Test Library**: [library for the settled language]

[Iterations, tagging, generators, mocks; or the reason the feature does not
suit property-based testing]

### Unit testing

### Integration testing

## Performance Considerations

## Security Considerations

## Dependencies

## Open Questions and Assumptions

### Open questions

- [Question whose answer changes the architecture, with the option taken
  provisionally]

### Assumptions

- [Assumption, and the requirement clause it fills a gap in]
```

## Section guidance

**Overview.** Address the whole requirements document. Name the glossary
terms rather than paraphrasing them, so a reader can grep from a requirement
to the design.

**Architecture.** Mermaid for diagrams. Diagrams show the real mechanism:
every box is a component named in the next section, every arrow a call or
message the components actually exchange.

**Components and Interfaces.** One subsection per component the glossary
names, in the notation settled in step 2. Where the glossary names a
subsystem rather than a component, a subsection may group several.

**Data Models.** One subsection per record the glossary names, plus any
record the design introduces. Validation rules carry the bounds the
acceptance criteria state (lengths, sizes, ranges, caps) with the clause
number.

**Error Handling.** Group scenarios by stage. Every IF/THEN acceptance
criterion maps to a scenario here.

**Testing Strategy.** Say which clauses are covered by property tests, which
by example tests, and which by integration or smoke tests, so the union
covers every clause. Decision logic is designed as pure functions with
external services behind interfaces so that it stays testable.

## The property-based testing gate

| Appropriate | Not appropriate |
| --- | --- |
| Pure functions with clear input/output behaviour | Infrastructure as code (Terraform, CDK, CloudFormation, Pulumi) |
| Parsers, serializers, data transformations | UI rendering and layout |
| Algorithms, business logic | Simple CRUD with no transformation logic |
| Features with universal properties over a wide input space | Configuration validation |
| | Side-effect-only operations |

A feature may contain both kinds. Write properties for the pure decision
logic and leave the integration-shaped behaviour to the example and
integration tests; name that split in Testing Strategy.

When the gate passes:

- Each property is universally quantified and contains an explicit "for
  all" (or "for any").
- Each property derives from specific acceptance criteria and ends with
  `**Validates: Requirements X.Y, X.Z**` naming them. Consolidate criteria
  that state the same universal into one property.
- Testing Strategy states the property test library (an existing one, never
  written from scratch), a minimum of 100 iterations per property, one
  property per test, and the tag format
  `**Feature: {feature_name}, Property {number}: {property_text}**`.

When the gate fails: the section is omitted, Testing Strategy specifies unit
and integration tests only, and states why property-based testing does not
apply.

## Parsers and serializers

Where the design introduces a parser or serializer, the design names the
grammar, includes a pretty printer, and carries a round-trip property:

```text
For all valid [Object] values, parsing then printing then parsing
produces an equivalent value (round-trip property).
```
