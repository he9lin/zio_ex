# ZioEx

A ZIO-inspired effect system for Elixir. Build composable programs with typed errors, dependency injection, and resource safety.

**Effect** — Define effects with `succeed`, `fail`, `sync`, `access`, `flat_map`, `fold`, `retry`, `ensuring`, and `zip_par` (parallel execution).

**Layer** — Compose dependencies with horizontal (`and_`) and vertical (`to`) composition. Use `memoize` for single-execution layers.

**Ref** — Mutable reference backed by Agent: `make`, `get`, `update`.

**Runtime** — Run effects via `ZioEx.Runtime.run/2` with an optional environment map.

## Installation

```elixir
def deps do
  [
    {:zio_ex, "~> 0.1.0"}
  ]
end
```
