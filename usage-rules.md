# Ecto Code Generation Rules for LLM

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

### Primary Schema Structure
```elixir
schema "table_name" do
  field :name, :string                    # Use appropriate Ecto type
  field :count, :integer, default: 0      # Specify defaults when needed
  field :metadata, :map                   # Use :map for JSON/JSONB
  field :tags, {:array, :string}          # Arrays with element type
  field :status, Ecto.Enum, values: [:draft, :published]  # Use Ecto.Enum for constrained values
  field :computed, :string, virtual: true # Virtual fields don't persist
  field :password, :string, redact: true  # Redact sensitive fields
  
  belongs_to :user, User                  # Foreign key: user_id
  has_many :posts, Post                   # One-to-many
  has_one :profile, Profile               # One-to-one
  many_to_many :tags, Tag, join_through: "posts_tags"  # Many-to-many
  
  timestamps()  # ALWAYS include for created_at/updated_at
end
```

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

### Multiple Changesets for Different Operations
```elixir
# PREFER separate changesets over conditional logic
def registration_changeset(user, params) do
  user
  |> cast(params, [:email, :password])
  |> validate_required([:email, :password])
  |> unique_constraint(:email)
end

def update_changeset(user, params) do
  user
  |> cast(params, [:name, :bio])
  |> validate_length(:bio, max: 500)
end
```

## QUERY PATTERNS

### Query Composition Rules
```elixir
# BUILD queries incrementally
def base_query, do: from(p in Post, where: p.published == true)
def by_author(query, author_id), do: from(q in query, where: q.author_id == ^author_id)
def recent(query), do: from(q in query, order_by: [desc: q.inserted_at])

# COMPOSE queries
Post |> base_query() |> by_author(123) |> recent() |> Repo.all()
```

### Dynamic Query Building
```elixir
# USE dynamic for complex conditional queries
def filter(query, params) do
  dynamic = true
  
  dynamic = 
    if params[:name] do
      dynamic([p], ^dynamic and p.name == ^params[:name])
    else
      dynamic
    end
    
  from(q in query, where: ^dynamic)
end
```

### Preloading Strategies
```elixir
# PREFER query-level preloads
Repo.all(from p in Post, preload: [:author, comments: :user])

# USE Repo.preload for existing structs
posts |> Repo.preload([:author, :comments])

# AVOID nested preloads unless necessary
# BAD: preload: [author: [posts: :comments]]
```

## MIGRATION PATTERNS

### Migration Structure
```elixir
def change do
  create table(:posts) do
    add :title, :string, null: false     # Specify constraints
    add :body, :text                     # Use :text for long strings
    add :view_count, :integer, default: 0
    add :user_id, references(:users, on_delete: :delete_all), null: false
    
    timestamps()
  end
  
  create index(:posts, [:user_id])       # ALWAYS index foreign keys
  create unique_index(:posts, [:slug])   # Unique constraints need indexes
end
```

### Safe Production Migrations
```elixir
# USE concurrent index creation for large tables
create index(:posts, [:created_at], concurrently: true)

# SEPARATE structure and data migrations
# Migration 1: Add column with default
# Migration 2: Backfill data
# Migration 3: Add not null constraint
```

## REPOSITORY OPERATIONS

### Insert/Update Patterns
```elixir
# PATTERN: Handle success and failure
case Repo.insert(changeset) do
  {:ok, struct} -> # success path
  {:error, changeset} -> # handle errors
end

# USE bang functions only when failure is unexpected
user = Repo.insert!(changeset)  # Will raise on error
```

### Upsert Patterns
```elixir
# ALWAYS specify conflict_target and on_conflict
Repo.insert(changeset,
  on_conflict: [set: [updated_at: DateTime.utc_now()]],
  conflict_target: [:email],
  returning: true
)

# BULK upserts
Repo.insert_all(Post, posts,
  on_conflict: :replace_all,
  conflict_target: [:external_id]
)
```

## TESTING PATTERNS

### Factory Pattern
```elixir
def user_factory(attrs \\ %{}) do
  %User{
    email: "user#{System.unique_integer()}@example.com",  # ENSURE uniqueness
    name: "Test User"
  }
  |> Map.merge(attrs)
end

def insert_user(attrs \\ %{}) do
  user_factory(attrs) |> Repo.insert!()
end
```

### SQL Sandbox Setup
```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  
  # For async tests with other processes
  Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
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

# ALWAYS scope queries
def posts_for_org(org_id) do
  from(p in Post, where: p.org_id == ^org_id)
end
```

### Query Prefix Multi-tenancy
```elixir
# USE for schema-based isolation
Repo.all(Post, prefix: "tenant_#{tenant_id}")
Repo.insert(changeset, prefix: tenant_prefix)
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

### Ecto.Multi for Complex Operations
```elixir
Multi.new()
|> Multi.insert(:user, user_changeset)
|> Multi.run(:profile, fn repo, %{user: user} ->
  # Dependent operation
  repo.insert(%Profile{user_id: user.id})
end)
|> Repo.transaction()
|> case do
  {:ok, %{user: user, profile: profile}} -> # Success
  {:error, failed_step, changeset, _} -> # Handle failure
end
```

## PRIORITY INDICATORS FOR CODE GENERATION

When generating Ecto code:
1. **SECURITY FIRST**: Never compromise on parameter casting, always use changesets
2. **DATA INTEGRITY SECOND**: Always use database constraints, handle race conditions
3. **PERFORMANCE THIRD**: Prevent N+1 queries, use bulk operations when possible
4. **CLARITY FOURTH**: Separate concerns, use multiple changesets, compose queries

## COMMON LLM MISTAKES TO AVOID

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
