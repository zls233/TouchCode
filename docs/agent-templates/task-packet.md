# Task packet

## Outcome

<!-- One concrete, verifiable outcome. -->

## Risk level

<!-- Level 1 Routine / Level 2 Stateful-Cross-module / Level 3 Architecture-Security -->

## Architecture decision

<!-- Level 3 only: frozen minimum decision and the conditions that may reopen it. -->

## Scope

Allowed:

- <!-- Files/modules/behaviors that may change. -->

Do not touch:

- <!-- Explicit boundaries and unrelated work. -->

## Relevant files

- <!-- Implementation, interfaces, tests, config, approved plan. -->

## Invariants

1. <!-- Property that must remain true. -->

## Known edge cases

- <!-- Failure, lifecycle, race, compatibility, or input edge. -->

## Acceptance criteria

- [ ] <!-- Observable completion condition. -->

## Validation

During development:

- <!-- Targeted tests/typecheck. -->

Before review:

- <!-- Targeted plus affected-package checks. -->

Before merge:

- <!-- Full repository/native/integration checks justified by scope. -->

For async or stateful work, use deterministic controllable fakes for important
transitions instead of immediate no-op mocks.
