# Trading App Implementation Plan (Java Spring + JPA + PostgreSQL + React)

## Summary
Build an MVP full-stack trading app using:
- Backend: Java 17, Spring Boot 3, Spring Data JPA, Spring Security
- DB: PostgreSQL (using existing schema in `ddl_scripts.sql`)
- Frontend: React + TypeScript
- Auth: Google OAuth2 and local login with **email or username + password**

Plan output target file: `IMPLEMENTATION_PLAN.md` (repo root), modeled after `ONECODE_IMPLEMENTATION_PLAN.md`.

## Inputs and Baseline
- Use `ONECODE_IMPLEMENTATION_PLAN.md` as style/reference baseline.
- Treat `ddl_scripts.sql` as authoritative for domain tables/views/triggers already created.
- Keep existing table semantics (amount precision, strategy tables, opportunities views, price peak trigger).

## Public API / Interface Changes
1. New auth API surface:
- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/oauth2/google`
- `GET /api/auth/oauth2/callback`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/me`

2. Trading API (JWT-protected):
- `GET /api/assets`
- `GET /api/exchanges`
- `GET /api/transactions`
- `POST /api/transactions/buy`
- `POST /api/transactions/sell`
- `GET /api/portfolio/summary`
- `GET /api/portfolio/performance`
- `GET /api/strategies/sell`, `POST /api/strategies/sell`
- `GET /api/strategies/buy`, `POST /api/strategies/buy`
- `GET /api/strategies/alerts`
- `POST /api/strategies/alerts/{id}/acknowledge`

3. New backend interfaces/types:
- `AuthProvider` enum: `LOCAL`, `GOOGLE`
- `UserPrincipal` for Spring Security context
- DTO groups: `auth`, `transaction`, `portfolio`, `strategy`
- Repository projections for portfolio and opportunities views

## Detailed Implementation Plan

## Phase 1: Project Scaffolding
1. Backend module:
- Spring Boot starter set: web, data-jpa, security, oauth2-client, validation, flyway, postgres driver.
- Package layout aligned with reference plan:
  - `config`, `security`, `domain/entity`, `domain/repository`, `dto`, `service`, `controller`, `exception`.

2. Frontend module:
- React + TypeScript + Vite.
- Structure: `pages`, `components`, `services`, `hooks`, `context`, `types`.

3. Environment config:
- Backend envs: DB URL/user/pass, JWT secret, Google client id/secret, CORS origin.
- Frontend env: API base URL.

## Phase 2: Database and Migration Strategy
1. Flyway migration sequence:
- `V1__domain_schema.sql`: import/adapt `ddl_scripts.sql` into migration-safe form.
- `V2__auth_schema.sql`: create auth tables.
- `V3__multi_tenant_user_fk.sql`: add `user_id` to user-owned domain tables and update views.
- `V4__indexes_and_constraints.sql`: add auth and `user_id` indexes.

2. Auth schema design:
- `users`:
  - `id UUID PK`
  - `email VARCHAR(255) UNIQUE NOT NULL`
  - `username VARCHAR(50) UNIQUE NOT NULL`
  - `password_hash VARCHAR(255) NULL` (NULL allowed for Google-only accounts)
  - `is_enabled`, `created_at`, `updated_at`
- `oauth_accounts`:
  - `id UUID PK`
  - `user_id FK users(id)`
  - `provider VARCHAR(20)` (`GOOGLE`)
  - `provider_user_id VARCHAR(255)`
  - unique `(provider, provider_user_id)`
- `refresh_tokens`:
  - hashed token storage, expiry, revoke support

3. Multi-tenant ownership:
- Add `user_id UUID NOT NULL` with FK to:
  - `transactions`, `accumulation_trades`, `sell_strategies`, `buy_strategies`, `strategy_alerts`, `price_peaks`
- Update `user_portfolio_performance`, `sell_opportunities`, `buy_opportunities` views to include `user_id`.
- Index `(user_id, created_at)` or `(user_id, status)` based on query paths.

## Phase 3: Security and Authentication
1. JWT-based stateless auth:
- Access token short TTL.
- Refresh token persisted hashed in DB.
- Security filter chain:
  - Public: `/api/auth/**`, OAuth callback
  - Protected: all domain APIs
  - CSRF disabled for stateless API, strict CORS enabled.

2. Local auth flows:
- Register: validate unique `email` and `username`, hash password (BCrypt), create user.
- Login: accept `identifier` (email or username) + password.
- Refresh: rotate refresh token.
- Logout: revoke refresh token.

3. Google OAuth2 flow:
- On callback:
  - find/create user by email
  - ensure `oauth_accounts` link exists
  - issue JWT + refresh token
- Account linking policy:
  - same email joins existing local account if present.

## Phase 4: Domain and Service Layer
1. JPA entities:
- Map existing domain tables from `ddl_scripts.sql`.
- Add `@ManyToOne User user` to user-owned entities.
- Keep `BigDecimal` + explicit scale handling in service calculations.

2. Core services:
- `AuthService`, `JwtService`, `OAuthUserService`
- `TransactionService`: buy/sell recording and realized PnL
- `PortfolioService`: aggregates from updated views
- `StrategyService`: strategy CRUD and alert generation
- `AccumulationTradeService`: open/close swing lifecycle

3. Transaction boundaries:
- `@Transactional` on buy/sell and accumulation completion flows.
- Validate ownership on every read/write by `user_id`.

## Phase 5: REST Controllers and Validation
1. Controllers:
- `AuthController`, `TransactionController`, `PortfolioController`, `StrategyController`, `LookupController`.
2. Validation:
- Bean validation on DTOs (amount > 0, threshold > 0, enum checks).
3. Error contracts:
- Unified error payload: `code`, `message`, `details`, `timestamp`.
- 401/403 for auth/authorization; 422 for domain validation.

## Phase 6: React Frontend MVP
1. Pages:
- `Login`, `Register`, `Dashboard`, `Transactions`, `Strategies`.
2. Auth UX:
- Login form with identifier field ("Email or username").
- "Continue with Google" button.
- Auth context + protected routes.
3. Trading UX:
- Buy/sell forms, transaction list, portfolio summary cards.
- Strategy forms and pending alerts list.
4. API client:
- Axios interceptor for JWT attach + refresh retry.
- Central typed services for auth/trading endpoints.

## Phase 7: Testing and Acceptance
1. Backend unit tests:
- Auth logic (register/login/google linkage).
- Transaction fee math and realized PnL.
- Portfolio aggregation and strategy trigger logic.

2. Backend integration tests (Testcontainers Postgres):
- Flyway migrations apply cleanly.
- Auth endpoints and protected routes.
- User isolation (`user_id` scope enforcement).

3. Frontend tests:
- Auth flows (local + Google redirect initiation).
- Protected route behavior.
- Buy/sell form validation and submission.

4. MVP acceptance criteria:
- User can register/login with email or username/password.
- User can login with Google.
- Authenticated user can create and list own transactions only.
- Portfolio and strategy data are user-scoped.
- No precision loss in monetary calculations.

## Phase 8: Delivery Sequence (MVP)
1. Week 1: Project scaffold + Flyway `V1/V2`.
2. Week 2: Security + local auth + JWT/refresh.
3. Week 3: Google OAuth + account linking + `/auth/me`.
4. Week 4: Transaction/portfolio backend + ownership enforcement.
5. Week 5: React auth + dashboard + transactions.
6. Week 6: Strategies + tests + hardening.

## Assumptions and Defaults
- Local login mode: **Email or Username + Password**.
- First delivery scope: **MVP + delivery plan** (not full production SRE program).
- Plan file target: **`IMPLEMENTATION_PLAN.md`**.
- Existing `ddl_scripts.sql` is baseline schema and will be migrated under Flyway, not replaced.
- OAuth provider for this phase is Google only.
