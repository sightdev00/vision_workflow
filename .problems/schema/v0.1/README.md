# Problem Epistemic State Schema v0.1

## Purpose

Define a persistent state model for complex engineering problems.

The schema separates:

- Reality facts (manifest, repository state)
- Human understanding (hypothesis, interpretation)
- Execution history (session, evidence)
- Responsibility (decision)
- Reusable knowledge (experience candidate)

## Core Model

```
Problem
 ├── Context
 ├── System Model
 ├── Hypothesis
 ├── Interpretation
 ├── Session
 │    └── Evidence
 ├── Decision
 └── Experience Candidate
```

## Design Principles

1. Evidence is not interpretation.
2. Hypothesis is not fact.
3. Decision requires rationale and ownership.
4. Experience must trace back to evidence.
5. Schema evolution is recorded through schema-feedback.
