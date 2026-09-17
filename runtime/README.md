# Runtime

The V0 runtime is a small Bash orchestration layer around Incus system
containers.

Lifecycle:

1. Resolve and validate a local scenario.
2. Create an Incus instance.
3. Install declared packages inside the instance.
4. Copy only scenario assets into the instance.
5. Execute guest lifecycle scripts through `incus exec ... -- bash -s`.
6. Execute host verifiers from the host perspective.
7. Hand the learner an interactive shell.
8. Verify final state on request.
9. Destroy the disposable environment on request.

Scenario lifecycle scripts receive a tiny explicit interface:

- `LINTENDO_INSTANCE_NAME`
- `LINTENDO_INSTANCE_IP`
- `LINTENDO_SCENARIO_DIR`

Host scripts also receive the instance name and IP as positional arguments:

```sh
host/verify.sh "$LINTENDO_INSTANCE_NAME" "$LINTENDO_INSTANCE_IP"
```

Scripts must not read Lintendo's internal state file.

