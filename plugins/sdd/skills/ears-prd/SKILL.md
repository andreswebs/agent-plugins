---
name: ears-prd
description: Write an EARS requirements.md (Product Requirements Document) with numbered, traceable acceptance criteria. Use when the user asks to write a PRD, requirements, or a feature spec, or mentions EARS format.
---

# EARS PRD Skill

Write a `requirements.md` whose acceptance criteria are EARS sentences, each addressable as clause `N.M` so a technical design and its tests can trace back to it.

## Workflow

1. **Match the house format.** Look for existing requirements documents in the repository. When one exists, its structure wins over the template below wherever they differ; note the differences you followed. Read whatever else informs the requirements: decision records, prior specs, the code. Done when the template to follow (house or skill) is stated in the conversation.

2. **Pick the branch.**
   - _Settled_: the decisions are already made (decision records, a prior interview, an approved plan). Write a complete draft that carries no `(NEEDS CLARIFICATION)` markers; anything still open goes to the user as a question, not into the document.
   - _Exploratory_: the user brings a rough idea. Write the draft without asking first, and mark each gap or ambiguity inline with `(NEEDS CLARIFICATION)`.

   Done when the branch is stated in the conversation.

3. **Write the draft** following the template. Consider edge cases, error paths, constraints and success criteria. Done when every requirement has a user story and numbered criteria, every Glossary term is used in the body, and the final requirement states the scope boundaries.

4. **Refine to approval.** Present the draft. In the exploratory branch, list the marked gaps, ask targeted questions with options where the user is unsure, and update the document. Repeat until the user explicitly approves. Done when the user has approved and no `(NEEDS CLARIFICATION)` marker remains.

## Template

```markdown
# [Product/Feature Name] ([release, when it targets one]) - Requirements

## Introduction

[2-3 paragraphs: the problem, who has it, what this document adds]

## Glossary

- **[Term]**: [definition, in the words the criteria use]

## Requirements

### Requirement 1: [Name]

**User Story**: As a <role>, I want <feature>, so that <benefit>.

#### Acceptance Criteria

1. The system shall <response>.
2. WHEN <trigger>, the system shall <response>.
3. IF <failure>, THEN the system shall <response>.

### Requirement N: Scope Boundaries

**User Story**: As a maintainer, I want the boundaries of this release stated, so that <benefit>.

#### Acceptance Criteria

1. The system shall not, in this release, provide <excluded capability>.

## Acceptance Tests

### [Scenario name]

[Prose: a concrete end-to-end run over named fixtures or inputs, and the observable outcomes that prove a group of requirements together.]
```

Number requirements and criteria consecutively, each number unique within the document, since designs cite `N.M`. The Acceptance Tests section is optional; include it when end-to-end scenarios prove something the individual criteria do not.

## Content Guidelines

State WHAT the product does and WHY, not HOW it is built: no internal components, data stores or code structure.

The user-facing interface is part of the WHAT when the interface is the product's contract. For a CLI, a file format, a library or an API, name the commands, flags, files, exit codes, fields and signatures the user relies on.

The actor of a criterion is the system. When a criterion constrains another deliverable, such as a user guide, name that deliverable as the actor: "The user guide shall state ...".

## EARS Syntax Reference

Format acceptance criteria using these patterns:

| Pattern      | Template                                                                 |
| ------------ | ------------------------------------------------------------------------ |
| Ubiquitous   | The system shall `<response>`.                                           |
| State-driven | WHILE `<precondition>`, the system shall `<response>`.                   |
| Event-driven | WHEN `<trigger>`, the system shall `<response>`.                         |
| Optional     | WHERE `<feature>`, the system shall `<response>`.                        |
| Unwanted     | IF `<error/failure>`, THEN the system shall `<response>`.                |
| Complex      | WHILE `<precondition>`, WHEN `<trigger>`, the system shall `<response>`. |

For full syntax details, see [references/ears.syntax.md](references/ears.syntax.md).
