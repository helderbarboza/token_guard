# TokenGuard

[![Tests](https://github.com/helderbarboza/token_guard/actions/workflows/ci.yml/badge.svg)](https://github.com/helderbarboza/token_guard/actions/workflows/ci.yml)

A lightweight token pool management system built with Elixir and Phoenix.

## Overview

TokenGuard is a **token pool management API** that manages a pool of pre-generated tokens that can be "activated" (checked out) by users. It's designed for scenarios where you need to:

- Manage shared resources like licenses, seats, or access passes
- Track who used which resource and when
- Automatically reclaim inactive resources
- Implement FIFO allocation policies

## Stack

- **Elixir** 1.15+ / **Erlang** OTP 26+
- **Phoenix** v1.8 (web framework)
- **Ecto** (database ORM)
- **PostgreSQL** 14+ (database)
- **Oban** (background job processing)
- **LiveDashboard** (monitoring)

## Features

- **Token Pool**: Pre-configured pool of 100 tokens (easily scalable)
- **FIFO Allocation**: Tokens are allocated in first-in-first-out order
- **Automatic Expiration**: Tokens automatically expire after 2 minutes from activation time
- **Usage History**: Full audit trail of token usage with start/end timestamps
- **Admin Controls**: Endpoints to release all active tokens instantly
- **Background Processing**: Oban-powered background job for token cleanup

## Getting Started

### Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- PostgreSQL 14+

### Installation

1. **Install all dependencies and setup the project:**

```bash
mix setup
```

This will:
- Install Elixir dependencies (`mix deps.get`)
- Create the database
- Run migrations
- Seed 100 tokens
- Setup and build frontend assets

2. **Configure the database (if needed):**

Update `config/dev.exs` with your PostgreSQL credentials:

```elixir
config :token_guard, TokenGuard.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "token_guard_dev"
```

3. **Start the server:**

```bash
mix phx.server
```

Or run in interactive mode:

```bash
iex -S mix phx.server
```

4. **Visit the API at** [`http://localhost:4000`](http://localhost:4000)

### Development Tools

- **LiveDashboard**: [`http://localhost:4000/dev/dashboard`](http://localhost:4000/dev/dashboard)
- **Oban Dashboard**: [`http://localhost:4000/dev/oban`](http://localhost:4000/dev/oban)
- **HTTP Client**: Use [`api.http`](./api.http) with [REST Client](https://marketplace.visualstudio.com/items?itemName=humao.rest-client) for VS Code to test the API endpoints.

## API Reference

### Activate a Token (`POST /api/tokens/register`)

Register a user and receive an allocated token.

```mermaid
sequenceDiagram
    title Token Activation (Register)
    autonumber
    participant Client as External Service
    participant API as Phoenix API
    participant Tokens as Tokens Context
    participant Repo as Ecto Repo
    participant DB as PostgreSQL

    Client->>API: POST /api/tokens/register<br/>{"user_id": "uuid"}
    
    API->>API: Validate ActivationParams<br/>(check UUID format)
    
    alt Invalid user_id
        API->>Client: 422 Unprocessable Entity<br/>{"errors": {"user_id": [...]}}
    end
    
    API->>Tokens: activate_token(user_id)
    
    Tokens->>Repo: transaction(fn)
    
    rect rgba(200, 230, 200, 0.3)
        Note over Repo,DB: Fetch available token
        Tokens->>Repo: SELECT available tokens<br/>ORDER BY inserted_at LIMIT 1
        Repo->>DB: Query
        DB->>Repo: First available token
        Repo->>Tokens: Token struct
    end
    
    alt No available tokens
        Note over Tokens: Release oldest active token (FIFO)
        Tokens->>Repo: SELECT active tokens<br/>ORDER BY inserted_at LIMIT 1
        Repo->>DB: Query
        DB->>Repo: Oldest active token
        Tokens->>Tokens: release_token(oldest)
        Tokens->>Repo: UPDATE token status = available
        Tokens->>Repo: UPDATE usage ended_at = now
        Tokens->>Repo: commit
    end
    
    rect rgba(200, 220, 255, 0.3)
        Note over Repo,DB: Activate token
        Tokens->>Repo: UPDATE token status = active
        Repo->>DB: Update
        Tokens->>Repo: INSERT token_usage record
        Repo->>DB: Insert
    end
    
    Repo-->>Tokens: %{token_id, user_id}
    Tokens-->>API: {:ok, result}
    API-->>Client: 200 OK<br/>{"token_id": "...", "user_id": "..."}
```

**Request:**

```http
POST /api/tokens/register
Content-Type: application/json

{
  "user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Response:**

```json
{
  "token_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

---

### List All Tokens (`GET /api/tokens`)

Get the status of all tokens in the pool.

```mermaid
sequenceDiagram
    title List All Tokens
    autonumber
    participant Client as External Service
    participant API as Phoenix API
    participant Tokens as Tokens Context
    participant Repo as Ecto Repo
    participant DB as PostgreSQL

    Client->>API: GET /api/tokens
    
    API->>Tokens: list_tokens()
    Tokens->>Repo: Repo.all(Token)
    Repo->>DB: SELECT * FROM tokens
    DB->>Repo: [100 tokens]
    Repo->>Tokens: [tokens]
    Tokens->>API: [tokens]
    
    API->>API: Map tokens to response format
    
    API-->>Client: 200 OK<br/>{"tokens": [...]}
```

**Request:**

```http
GET /api/tokens
```

**Response:**

```json
{
  "tokens": [
    {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
      "status": "available",
      "inserted_at": "2024-04-01T10:00:00Z",
      "updated_at": "2024-04-01T10:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "status": "active",
      "inserted_at": "2024-04-01T10:00:00Z",
      "updated_at": "2024-04-01T12:30:00Z"
    }
  ]
}
```

---

### Get Token Details (`GET /api/tokens/:id`)

Retrieve details for a specific token, including active user if any.

```mermaid
sequenceDiagram
    title Query Token Status
    autonumber
    participant Client as External Service
    participant API as Phoenix API
    participant Tokens as Tokens Context
    participant Repo as Ecto Repo
    participant DB as PostgreSQL

    Client->>API: GET /api/tokens/:id
    
    API->>Tokens: get_token_by_id(id)
    Tokens->>Repo: Repo.get(Token, id)
    Repo->>DB: SELECT * FROM tokens WHERE id = ?
    DB->>Repo: Token struct or nil
    Repo->>Tokens: Token or nil
    Tokens->>API: Token or nil
    
    alt Token not found
        API-->>Client: 404 Not Found<br/>{"error": "Token not found"}
    end
    
    API->>Tokens: get_active_usage_for_token(id)
    Tokens->>Repo: SELECT * FROM token_usages<br/>WHERE token_id = ?<br/>AND ended_at IS NULL
    Repo->>DB: Query
    DB->>Repo: Active usage or nil
    Repo->>Tokens: TokenUsage or nil
    Tokens->>API: TokenUsage or nil
    
    API-->>Client: 200 OK<br/>{"id": "...", "status": "active", "active_user": {...}, ...}
```

**Request:**

```http
GET /api/tokens/f47ac10b-58cc-4372-a567-0e02b2c3d479
```

**Response (available token):**

```json
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "status": "available",
  "active_user": null,
  "inserted_at": "2024-04-01T10:00:00Z",
  "updated_at": "2024-04-01T10:00:00Z"
}
```

**Response (active token):**

```json
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "status": "active",
  "active_user": {
    "user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "started_at": "2024-04-01T12:30:00Z"
  },
  "inserted_at": "2024-04-01T10:00:00Z",
  "updated_at": "2024-04-01T12:30:00Z"
}
```

---

### Get Token History (`GET /api/tokens/:id/history`)

View the usage history for a specific token.

```mermaid
sequenceDiagram
    title Token History
    autonumber
    participant Client as External Service
    participant API as Phoenix API
    participant Tokens as Tokens Context
    participant Repo as Ecto Repo
    participant DB as PostgreSQL

    Client->>API: GET /api/tokens/:id/history
    
    API->>Tokens: get_token_by_id(id)
    Tokens->>Repo: Repo.get(Token, id)
    Repo->>DB: SELECT * FROM tokens WHERE id = ?
    DB->>Repo: Token or nil
    Tokens->>API: Token or nil
    
    alt Token not found
        API-->>Client: 404 Not Found
    end
    
    API->>Tokens: get_token_history(id)
    Tokens->>Repo: SELECT * FROM token_usages<br/>WHERE token_id = ?<br/>ORDER BY started_at DESC
    Repo->>DB: Query
    DB->>Repo: [usage1, usage2, ...]
    Repo->>Tokens: [usage_records]
    Tokens->>API: [usage_records]
    
    API-->>Client: 200 OK<br/>{"history": [...]}
```

**Request:**

```http
GET /api/tokens/f47ac10b-58cc-4372-a567-0e02b2c3d479/history
```

**Response:**

```json
{
  "history": [
    {
      "user_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "started_at": "2024-04-01T14:00:00Z",
      "ended_at": "2024-04-01T14:02:00Z"
    },
    {
      "user_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "started_at": "2024-04-01T12:30:00Z",
      "ended_at": "2024-04-01T12:32:00Z"
    }
  ]
}
```

---

### Release All Active Tokens (`DELETE /api/tokens/active`)

Immediately release all active tokens (admin operation).

```mermaid
sequenceDiagram
    title Release All Active Tokens
    autonumber
    participant Admin as Admin/Service
    participant API as Phoenix API
    participant Tokens as Tokens Context
    participant Repo as Ecto Repo
    participant DB as PostgreSQL

    Admin->>API: DELETE /api/tokens/active
    
    API->>Tokens: release_all_active_tokens()
    
    Tokens->>Tokens: list_active_tokens()
    Tokens->>Repo: SELECT * FROM tokens<br/>WHERE status = 'active'
    Repo->>DB: Query
    DB->>Repo: [token1, token2, token3]
    Repo->>Tokens: [active_tokens]
    
    loop For each active token
        Tokens->>Tokens: release_token(token)
        
        Tokens->>Repo: UPDATE tokens<br/>SET status = 'available'
        Repo->>DB: Update
        
        Tokens->>Repo: SELECT * FROM token_usages<br/>WHERE token_id = ?<br/>AND ended_at IS NULL
        Repo->>DB: Query
        DB->>Repo: [usage]
        
        Tokens->>Repo: UPDATE token_usages<br/>SET ended_at = now
        Repo->>DB: Update
    end
    
    Tokens->>API: 3
    API-->>Admin: 200 OK<br/>{"message": "3 token(s) released", "released_count": 3}
```

**Request:**

```http
DELETE /api/tokens/active
```

**Response:**

```json
{
  "message": "3 token(s) released",
  "released_count": 3
}
```

**Response (no active tokens):**

```json
{
  "message": "0 token(s) released",
  "released_count": 0
}
```

## Configuration

### Token Lifetime

The token lifetime determines how long a token can be active before being automatically released. The default is 2 minutes.

To configure, set in `config/config.exs`:

```elixir
config :token_guard,
  token_lifetime: :timer.minutes(2)
```

Or in `config/dev.exs` / `config/prod.exs` for environment-specific values.

## Token Lifecycle

```mermaid
sequenceDiagram
    participant User1 as User 1
    participant User2 as User 2
    participant Pool as Token Pool
    participant Timer as Oban Timer

    Note over Pool: 100 available tokens

    User1->>Pool: POST /api/tokens/register (user1_id)
    Pool->>Pool: Allocate token-001 to user1
    Note over Pool: 99 available, 1 active

    User2->>Pool: POST /api/tokens/register (user2_id)
    Pool->>Pool: Allocate token-002 to user2
    Note over Pool: 98 available, 2 active

    User1->>Pool: GET /api/tokens/token-001
    Pool-->>User1: {"status": "active", "user_id": user1}

    User1->>Pool: GET /api/tokens/token-001/history
    Pool-->>User1: {"history": [{"user_id": user1_id, "started_at": ...}]}

    Note over Timer: 2 minutes pass...

    Timer->>Pool: release_expired_tokens()
    Pool->>Pool: Release token-001<br/>Release token-002
    Note over Pool: 100 available, 0 active

    User1->>Pool: POST /api/tokens/register (user1_id)
    Pool->>Pool: Allocate token-001 to user1
    Note over Pool: 99 available, 1 active

    User2->>Pool: DELETE /api/tokens/active
    Pool->>Pool: Release all active tokens
    Note over Pool: 100 available, 0 active
```

### Pool Size

The pool size is set during database seeding. To create a different number of tokens:

```elixir
# In iex
TokenGuard.Tokens.create_tokens(50)
```

## Testing

Run the test suite:

```bash
mix test
```

Run with coverage:

```bash
mix coveralls.detail
```

## Quality Checks

This project uses the `mix precommit` alias for quality checks:

```bash
mix precommit
```

This runs:
- Compilation with warnings as errors
- Dependency check
- Code formatting
- Credo linting
- Dialyzer type checking
- Test suite
