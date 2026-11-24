# Validation

Use `Validation` for independent checks when the caller needs every error at once. `Validation.succeed/1` holds a checked value. `Validation.fail/1` wraps one error in a list. `validate_with/3` calls the combining function when both checks succeed and accumulates errors from left to right otherwise.

```elixir
alias ZioEx.Validation

check_name = fn
  "" -> Validation.fail({:name, :missing})
  name -> Validation.succeed(name)
end

check_age = fn
  age when is_integer(age) and age >= 0 -> Validation.succeed(age)
  _ -> Validation.fail({:age, :invalid})
end

person = fn name, age -> %{name: name, age: age} end

%Validation{result: {:ok, %{name: "Ada", age: 28}}} =
  Validation.validate_with(check_name.("Ada"), check_age.(28), person)

%Validation{result: {:error, [name: :missing, age: :invalid]}} =
  Validation.validate_with(check_name.(""), check_age.(-1), person)
```

For checks that perform effects, `Effect.validate_par/1` accepts a nonempty list of effects that return validation values. The validation errors are data inside a successful runtime result. If a check instead calls `Effect.fail/1`, the enclosing effect fails.

```elixir
alias ZioEx.{Effect, Runtime, Validation}

checks = [
  Effect.succeed(Validation.fail(:email_missing)),
  Effect.succeed(Validation.fail(:name_missing))
]

{:ok, %Validation{result: {:error, [:email_missing, :name_missing]}}} =
  Runtime.run(Effect.validate_par(checks))
```
