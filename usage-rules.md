## CRITICAL RULES - ALWAYS FOLLOW

### SECURITY CRITICAL - NEVER VIOLATE

- **NEVER** cast parameters without explicit field listing: `cast(changeset, params, [:field1, :field2])` - NOT `cast(changeset, params, Map.keys(params))`
- **NEVER** interpolate user input directly into queries - always use `^` for parameter binding
- **ALWAYS** use `redact: true` on password fields and sensitive data in schemas
- **ALWAYS** validate and cast external input through changesets before database operations

### DATA INTEGRITY CRITICAL

- **ALWAYS** pair `unsafe_validate_unique` with `unique_constraint` - validations alone cannot prevent race conditions
- **ALWAYS** use database constraints (`unique_constraint`, `foreign_key_constraint`, `check_constraint`) as the source of truth
- **NEVER** implement "get or create" without proper `on_conflict` handling or constraint-based error recovery
- **ALWAYS** use transactions (`Repo.transaction` or `Ecto.Multi`) for operations that must be atomic

### PERFORMANCE CRITICAL

- **ALWAYS** preload associations that will be accessed in loops to prevent N+1 queries
- **PREFER** `insert_all`, `update_all`, `delete_all` for bulk operations over iterating individual operations
- **ALWAYS** add indexes for foreign keys: `create index(:table, [:foreign_key_id])`
- **USE** `on_conflict` for upserts instead of separate get/insert operations

## SCHEMA DEFINITION RULES

### UUID Primary Keys (when needed)

```elixir
@primary_key {:id, :binary_id, autogenerate: true}
@foreign_key_type :binary_id
```

### Embedded Schemas Pattern

```elixir
# USE embedded schemas for: tightly coupled data, value objects, form data
embeds_one :address, Address
embeds_many :line_items, LineItem

# SEPARATE embedded schema module:
defmodule Address do
  use Ecto.Schema
  embedded_schema do  # Note: embedded_schema, not schema
    field :street, :string
    field :city, :string
  end
end
```

## CHANGESET PATTERNS - STRICT ORDERING

### Standard Changeset Pipeline

```elixir
def changeset(struct, params) do
  struct
  |> cast(params, [:field1, :field2])  # 1. ALWAYS list fields explicitly
  |> validate_required([:field1])       # 2. Required fields
  |> validate_length(:field1, min: 3)   # 3. Format validations
  |> validate_format(:email, ~r/@/)     # 4. More format validations
  |> unsafe_validate_unique(:email, Repo) # 5. DB validations (optional optimization)
  |> unique_constraint(:email)          # 6. CRITICAL: Always add constraint
  |> foreign_key_constraint(:user_id)   # 7. Referential integrity
end
```

## MULTI-TENANCY PATTERNS

### Foreign Key Multi-tenancy

```elixir
schema "posts" do
  field :org_id, :integer  # Tenant identifier
  field :title, :string
  belongs_to :user, User,
    foreign_key: :user_id,
    references: :id,
    with: [org_id: :org_id]  # Composite foreign key
end

```

## ERROR HANDLING PATTERNS

### Changeset Error Formatting

```elixir
# TRANSFORM errors for API/UI consumption
def format_errors(changeset) do
  Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end)
end
```

## TRANSACTION PATTERNS

### Modern Transact API (Preferred)

```elixir
# SIMPLE transaction with auto-wrapping return values
Repo.transact(fn ->
  user = Repo.insert!(user_changeset)
  profile = Repo.insert!(%Profile{user_id: user.id})
  {:ok, %{user: user, profile: profile}}  # Wrapped in {:ok, _}
end)
# Returns: {:ok, %{user: user, profile: profile}} or {:error, reason}

# EXPLICIT rollback
Repo.transact(fn ->
  user = Repo.insert!(user_changeset)
  if invalid_condition?(user) do
    Repo.rollback(:invalid_user)  # Returns {:error, :invalid_user}
  end
  {:ok, user}
end)

# REPO parameter variant (useful for testing/dependency injection)
Repo.transact(fn repo ->
  user = repo.insert!(user_changeset)
  {:ok, user}
end)
```

### Transaction Choice Guidelines

- **USE `Repo.transact/2`** for simple atomic operations with basic error handling
- **ALWAYS** handle both success `{:ok, _}` and failure `{:error, _}` cases
- **REMEMBER** `transact/2` auto-wraps successful returns, Multi requires explicit `{:ok, result}`

## PRIORITY INDICATORS FOR CODE GENERATION

When generating Ecto code:

1. **SECURITY FIRST**: Never compromise on parameter casting, always use changesets
2. **DATA INTEGRITY SECOND**: Always use database constraints, handle race conditions
3. **PERFORMANCE THIRD**: Prevent N+1 queries, use bulk operations when possible
4. **CLARITY FOURTH**: Separate concerns, use multiple changesets, compose queries

## COMMON MISTAKES TO AVOID

- DO NOT generate `cast(params, Map.keys(params))` - this is a critical security flaw
- DO NOT forget `timestamps()` in schemas
- DO NOT use `validate_unique` without `unique_constraint`
- DO NOT query in loops without preloading
- DO NOT mix embedded schemas and associations incorrectly
- DO NOT forget to index foreign keys
- DO NOT use string interpolation in queries - always use `^` for binding
- DO NOT implement get-or-create without proper race condition handling
- DO NOT use a single changeset for all operations - separate by use case
- DO NOT ignore the return values of Repo operations - handle both success and error cases
- DO NOT create unnecessary indexes unless it will be used in a known query
- DO NOT change schemas and/or migrations to fix a test.
- DO NOT use varchar for column type instead of text
- DO NOT use String.to_atom to change an Ecto.enum into an atom before a cast
