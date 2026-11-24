# Easy Approach to Requirements Syntax (EARS)

## Overview

A small number of keywords are used to denote the different clauses of an EARS requirement. The syntax and the keywords closely match common usage of English and are therefore intuitive. The clauses of a requirement always appear in the same order, following temporal logic.

A requirement refers to a statement that can fall under one of the following categories:

- What actions or functions a system is required to perform.
- Any known limitations or constraints on resources or design that may impact the system.
- The level of performance or quality that is expected of the system.

The first type of requirement is known as Functional Requirements while the second and third types fall under the category of Non-Functional Requirements (NFRs).

EARS differantiate five patterns of requirements

- Ubiquitous (always occurring): Defines fundamental properties of the system.
- State-driven: Triggered while in a certain state.
- Event-driven: Initiates when and only when a certain trigger event happens.
- Optional features: These are called upon exclusively within systems that have the specific optional feature.
- Unwanted behaviors: Manages undesired occurrences such as errors, failures, faults, disturbances, and other forms of unwanted behaviors.

The basic structure of an EARS requirement is:

```txt
[<optional precondition(s)>] [<optional trigger>] the <system name> shall <system response(s)>.
```

With the EARS keywords, the structure looks like this:

```txt
WHILE <optional pre-condition>, WHEN <optional trigger>, the <system name> shall <system response>.
```

The EARS ruleset states that a requirement must have: zero or many preconditions; zero or one trigger; one system name; one or many system responses.

The application of the EARS notation produces requirements in a small number of patterns, depending on the clauses that are used. The patterns are described below.

## Requirements Patterns

### Ubiquitous

Ubiquitous requirements are always active, i.e. it has no preconditions or trigger (so there is no EARS keyword).

```txt
The <system name> shall <system response>.
```

Example: The mobile phone shall have a mass of less than XX grams.

### State-driven

State-driven requirements are active as long as the specified state remains true and are denoted by the keyword WHILE.

```txt
WHILE <precondition(s)>, the <system name> shall <system response>.
```

Example: WHILE there is no card in the ATM, the ATM shall display "insert card to begin".

### Event-driven

Event-driven requirements specify how a system must respond when a triggering event occurs and are denoted by the keyword WHEN.

```txt
WHEN <trigger>, the <system name> shall <system response>.
```

Example: WHEN "mute" is selected, the laptop shall suppress all audio output.

### Optional feature

Optional feature requirements apply in products or systems that include the specified feature and are denoted by the keyword WHERE.

```txt
WHERE <feature is included>, the <system name> shall <system response>.
```

Example: WHERE the car has a sunroof, the car shall have a sunroof control panel on the driver door.

### Unwanted behaviour

Unwanted behaviour requirements are used to specify the required system response to undesired situations and are denoted by the keywords IF and THEN.

```txt
IF <trigger>, THEN the <system name> shall <system response>.
```

Example: IF an invalid credit card number is entered, THEN the website shall display "please re-enter credit card details".

### Complex requirements

The simple building blocks of the EARS patterns described above can be combined to specify requirements for richer system behaviour. Requirements that include more than one EARS keyword are called "Complex requirements".

```txt
WHILE <precondition(s)>, WHEN <trigger>, the <system name> shall <system response>.
```

Example: WHILE the aircraft is on ground, WHEN reverse thrust is commanded, the engine control system shall enable reverse thrust.

Complex requirements for unwanted behaviour also include the IF-THEN keywords.

The keywords WHEN, WHILE and WHERE can also be used within IF-THEN statements to handle unwanted behaviour with more complex conditional clauses.
