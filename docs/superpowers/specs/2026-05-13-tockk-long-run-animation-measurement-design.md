# Tockk Long-Run Animation Measurement Design

## Context

Tockk shows transient macOS notch-style notifications through `DynamicNotchKit`.
After the app has been left running for several days, notification show/hide
animation can become visibly choppy. A restart returns the app to a low-memory,
smooth baseline.

Recent live-process measurements showed a large difference between the long-run
and fresh-start states:

- Fresh restart: physical footprint about 15.5 MB, peak about 15.8 MB, about
  30k malloc nodes.
- Five-day run: physical footprint about 587 MB, peak about 1.6 GB, about
  2.26M malloc nodes.
- `leaks` reported zero leaks in both states, so this investigation should not
  treat the absence of explicit leaks as proof that no retain/task accumulation
  exists.

Source inspection identified one strong hypothesis: Tockk creates a new
`DynamicNotch` for each notification, while `DynamicNotchKit` starts a
screen-parameter observer task in each `DynamicNotch` initializer. That task is
not retained for cancellation and captures the instance strongly. The first goal
is to gather repeatable measurements that show whether notification count
correlates with sustained memory and rendering-resource growth in the installed
app.

## Goal

Create a local measurement workflow that can run against the currently installed
`/Applications/Tockk.app` without changing product code. The workflow should
send repeated notification events, sample process metrics before/during/after
the run, and leave logs that make a before/after fix comparison straightforward.

## Non-Goals

- Do not fix `NotchPresenter` or `DynamicNotchKit` in this design.
- Do not automatically quit, kill, relaunch, or reinstall Tockk.
- Do not commit local measurement logs.
- Do not rely on `leaks == 0` as a pass condition.
- Do not add public user-facing documentation for this local diagnostic flow.

## Target App

The primary target is the installed app:

```text
/Applications/Tockk.app/Contents/MacOS/Tockk
```

The measurement tool should find the running process by bundle identifier or
process path. If Tockk is not running, it should exit with a clear message asking
the operator to launch the app first.

Debug-build instrumentation is a fallback only. It should be used if external
metrics are inconclusive or if a later implementation needs to count internal
object lifetimes directly.

## Local Artifacts

The durable design lives in `docs/superpowers/specs/`.

Runtime artifacts should live under `.local/`, for example:

```text
.local/tockk-measurements/<timestamp>/
```

Each run directory should contain:

- a machine-readable summary file,
- raw `ps` samples,
- raw `vmmap -summary` samples,
- raw `leaks` output when available,
- a sent-event count and timing summary.

`.local/` is repository-local and must not be committed.

## Measurement Flow

1. Resolve the running Tockk PID.
2. Record a baseline sample before sending events.
3. Send newline-delimited JSON events to:

   ```text
   ~/Library/Application Support/Tockk/tockk.sock
   ```

4. Sample metrics at fixed intervals during the run.
5. Record a final sample immediately after the last event.
6. Wait for the configured cool-down period, then record a post-run sample.
7. Print a concise summary to the terminal and save the detailed output under
   `.local/tockk-measurements/<timestamp>/`.

The initial smoke run should send 100 events. If the result shows sustained
growth or is ambiguous, the same workflow should support a 500-event run.

## Event Cadence

The default cadence should prioritize real show/hide cycles over speed.

- Start with a 100-event smoke run.
- Use a per-event delay long enough for the existing notification to appear,
  dismiss, and allow the inter-alert gap to complete.
- Make the event count and delay configurable.

The measurement should avoid sending events so quickly that it only measures
queue pressure. Queue pressure can be a separate test later, but it is not the
primary long-run animation hypothesis.

## Metrics

At minimum, each sample should capture:

- PID,
- launch time or elapsed time,
- RSS,
- VSZ,
- physical footprint,
- peak physical footprint,
- malloc node count,
- malloced bytes,
- AttributeGraph malloc zone size/count,
- QuartzCore malloc zone size/count,
- CoreAnimation region size/count,
- IOSurface region size/count when present,
- `leaks` total leaked bytes when the tool can run it.

The summary should include deltas from baseline to final and from final to
post-cool-down.

## Interpretation

The smoke run should be considered suspicious if, after cool-down:

- physical footprint remains materially above baseline,
- malloc node count remains materially above baseline,
- AttributeGraph, QuartzCore, CoreAnimation, or IOSurface counts grow with event
  count and do not return near baseline,
- animation becomes visibly choppy during the run.

The workflow should not declare the app healthy only because `leaks` reports
zero leaks. Retained task graphs, observers, SwiftUI graph data, and rendering
resources can remain reachable and therefore not appear as classic leaks.

## Error Handling

The measurement tool should fail clearly when:

- Tockk is not running,
- more than one installed Tockk process is detected,
- the socket path does not exist,
- the socket refuses connections,
- `ps`, `vmmap`, or `leaks` is unavailable,
- a metric cannot be parsed from raw command output.

Raw output should still be saved when parsing fails, so the run remains useful
for manual inspection.

## Security and Safety

The workflow should only send local test events to Tockk's Unix socket. It should
not access network resources, secrets, user project files, or external services.
It should not alter user settings or hook configuration.

Commands that inspect a live process, such as `ps`, `vmmap`, `leaks`, and
`lsof`, may require local permission outside the sandbox. The workflow should
document that requirement rather than hiding it.

## Testing Strategy

The first implementation should include a dry-run mode that resolves the target
PID, prints the planned run configuration, and verifies the socket path without
sending events.

Parser logic should be testable against saved sample command output. The
measurement run itself can remain a local manual diagnostic because it depends
on a live GUI app and macOS process-inspection permissions.

## Exit Criteria

This measurement design is complete when there is a repeatable local command
that can:

- measure a fresh installed Tockk process,
- send 100 notification events through the real socket protocol,
- save before/during/after metrics under `.local/`,
- print a concise delta summary,
- support a later 500-event run using the same tool.

If the 100-event run shows sustained growth, the next design/implementation
step should focus on reducing `DynamicNotch` lifetime accumulation or patching
the `DynamicNotchKit` observer task lifecycle.
