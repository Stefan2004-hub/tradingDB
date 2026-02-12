# Trading App Implementation Plan by Points (<=30 Minutes Each)

## Summary
This file decomposes implementation into small, execution-ready points merged from:
- `IMPLEMENTATION_PLAN.md` (primary scope)
- `ddl_scripts.sql` (authoritative domain schema)
- `ONECODE_IMPLEMENTATION_PLAN.md` (expanded implementation detail)

Conflict priority:
1. `IMPLEMENTATION_PLAN.md`
2. `ddl_scripts.sql`
3. `ONECODE_IMPLEMENTATION_PLAN.md`

Each point below is capped at 30 minutes and includes a concrete completion check.

## Public API / Interface Baseline
- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/oauth2/google`
- `GET /api/auth/oauth2/callback`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/me`
- `GET /api/assets`
- `GET /api/exchanges`
- `GET /api/transactions`
- `POST /api/transactions/buy`
- `POST /api/transactions/sell`
- `GET /api/portfolio/summary`
- `GET /api/portfolio/performance`
- `GET /api/strategies/sell`
- `POST /api/strategies/sell`
- `GET /api/strategies/buy`
- `POST /api/strategies/buy`
- `GET /api/strategies/alerts`
- `POST /api/strategies/alerts/{id}/acknowledge`

## Types / Interfaces to Introduce
- `AuthProvider` enum: `LOCAL`, `GOOGLE`
- `UserPrincipal`
- DTO groups: `auth`, `transaction`, `portfolio`, `strategy`
- Projection models for `user_portfolio_performance`, `sell_opportunities`, `buy_opportunities`

## Execution Points
1. Backend package skeleton and base modules.
   - Estimate: 20m
   - Done when: package tree compiles and app starts.

2. Add backend dependencies (`web`, `data-jpa`, `security`, `oauth2-client`, `validation`, `flyway`, `postgresql`).
   - Estimate: 20m
   - Done when: dependency resolution succeeds.

3. Add environment variable matrix for backend/frontend configs.
   - Estimate: 20m
   - Done when: sample config loads without missing required keys.

4. Create Flyway migration map (`V1`..`V4`) and file stubs.
   - Estimate: 25m
   - Done when: all migration files exist in expected path.

5. Move base DDL for `btc_historic_data`, `assets`, `exchanges` into `V1` plan section.
   - Estimate: 25m
   - Done when: SQL section compiles in PostgreSQL parser.

6. Move `transactions` table and `realized_pnl` alteration into `V1` plan section.
   - Estimate: 20m
   - Done when: SQL syntax validates.

7. Move `user_portfolio_performance` view into `V1` plan section.
   - Estimate: 20m
   - Done when: view references valid tables/columns.

8. Move `accumulation_trades` + indexes into `V1` plan section.
   - Estimate: 20m
   - Done when: SQL syntax validates.

9. Move strategy tables (`sell_strategies`, `buy_strategies`, `strategy_alerts`, `price_peaks`) into `V1` plan section.
   - Estimate: 25m
   - Done when: all tables + indexes parse correctly.

10. Move `sell_opportunities` and `buy_opportunities` views into `V1` plan section.
   - Estimate: 25m
   - Done when: both views compile against schema.

11. Move peak reset function + trigger into `V1` plan section.
   - Estimate: 20m
   - Done when: function and trigger create successfully.

12. Define `V2` auth schema (`users`, `oauth_accounts`, `refresh_tokens`).
   - Estimate: 25m
   - Done when: all auth tables parse and FK constraints are valid.

13. Define `V3` multi-tenant `user_id` additions on user-owned tables.
   - Estimate: 25m
   - Done when: all required tables include `user_id` + FK.

14. Define `V3` view updates to enforce user scoping.
   - Estimate: 20m
   - Done when: updated views include `user_id` in output/filter path.

15. Define `V4` indexes for auth lookup and `user_id` query paths.
   - Estimate: 20m
   - Done when: index DDL parses and matches query patterns.

16. Security route matrix (`/api/auth/**` public, trading APIs protected).
   - Estimate: 20m
   - Done when: unauthorized access returns 401 on protected endpoints.

17. Implement JWT access token issue/validate service.
   - Estimate: 25m
   - Done when: token roundtrip validation passes unit test.

18. Implement refresh token hash storage and rotation.
   - Estimate: 25m
   - Done when: old refresh token is rejected after rotation.

19. Implement register flow (email + username uniqueness, BCrypt).
   - Estimate: 25m
   - Done when: duplicate checks and successful registration tests pass.

20. Implement login flow with `identifier` (email or username).
   - Estimate: 20m
   - Done when: both identifier modes authenticate successfully.

21. Implement logout flow with refresh token revoke.
   - Estimate: 15m
   - Done when: revoked token cannot refresh session.

22. Implement Google OAuth callback user create/link behavior.
   - Estimate: 25m
   - Done when: OAuth callback returns valid auth response.

23. Implement `UserPrincipal` + security-context user extraction helper.
   - Estimate: 20m
   - Done when: current user id is available in protected controllers.

24. Map JPA entities for core domain tables.
   - Estimate: 30m
   - Done when: app boots with entity scan and schema validate mode.

25. Add `@ManyToOne User` ownership mappings to user-owned entities.
   - Estimate: 25m
   - Done when: ownership FK mappings are validated at startup.

26. Implement repositories with mandatory `user_id` constrained methods.
   - Estimate: 25m
   - Done when: repository methods return only current user rows in tests.

27. Implement projection models for performance/opportunity views.
   - Estimate: 20m
   - Done when: native queries map cleanly to projection types.

28. Define `AuthService` interface + DTOs.
   - Estimate: 20m
   - Done when: controller compiles against DTO contracts.

29. Implement buy transaction service flow (gross/net/fees/spend).
   - Estimate: 30m
   - Done when: fee scenario unit tests pass.

30. Implement sell transaction service flow (balance + realized PnL).
   - Estimate: 30m
   - Done when: realized PnL unit tests pass.

31. Implement accumulation trade open flow.
   - Estimate: 25m
   - Done when: open trade is persisted and linked to sell tx.

32. Implement accumulation trade close flow.
   - Estimate: 25m
   - Done when: close updates delta and status correctly.

33. Implement sell strategy create/update flow.
   - Estimate: 20m
   - Done when: one active strategy per asset is enforced.

34. Implement buy strategy create/update flow.
   - Estimate: 20m
   - Done when: threshold/amount validations pass.

35. Implement strategy alert generation path.
   - Estimate: 30m
   - Done when: alert record appears for triggered condition.

36. Implement portfolio aggregation/performance service.
   - Estimate: 25m
   - Done when: response includes invested/current/unrealized metrics.

37. Implement `AuthController` endpoints.
   - Estimate: 25m
   - Done when: endpoint tests for register/login/refresh/logout/me pass.

38. Implement `TransactionController` endpoints.
   - Estimate: 25m
   - Done when: list/buy/sell endpoints return expected status + payload.

39. Implement `PortfolioController` endpoints.
   - Estimate: 20m
   - Done when: summary/performance endpoints return user-scoped data.

40. Implement `StrategyController` + alert acknowledge endpoint.
   - Estimate: 25m
   - Done when: acknowledge changes status and timestamps.

41. Implement lookup endpoints (`assets`, `exchanges`).
   - Estimate: 15m
   - Done when: endpoints return seeded data lists.

42. Add request validation and unified error response contract.
   - Estimate: 20m
   - Done when: invalid payloads return structured 4xx errors.

43. Add unit tests for auth logic and edge cases.
   - Estimate: 30m
   - Done when: auth service test suite passes.

44. Add unit tests for transaction math and PnL.
   - Estimate: 30m
   - Done when: all fee/PnL permutations pass.

45. Add unit tests for strategy trigger logic.
   - Estimate: 30m
   - Done when: trigger thresholds produce expected alerts.

46. Add integration test: Flyway migrations clean apply.
   - Estimate: 25m
   - Done when: test DB starts and migrates without errors.

47. Add integration test: security rules on protected endpoints.
   - Estimate: 25m
   - Done when: 401/403 matrix behaves as expected.

48. Add integration test: strict multi-tenant isolation.
   - Estimate: 25m
   - Done when: user A cannot read/write user B data.

49. Implement frontend auth flow slices (login/register/google entry/protected routes).
   - Estimate: 30m
   - Done when: unauthenticated users are redirected and login succeeds.

50. Implement frontend trading slices (buy/sell forms, history, summary cards).
   - Estimate: 30m
   - Done when: forms validate and render persisted data.

51. Implement frontend strategy slices (forms + pending alerts).
   - Estimate: 30m
   - Done when: strategy CRUD + alert acknowledge work from UI.

52. Implement frontend API client token attach + refresh retry.
   - Estimate: 25m
   - Done when: expired token auto-refreshes and request retries once.

53. Add MVP acceptance checklist section.
   - Estimate: 20m
   - Done when: all baseline acceptance criteria are measurable.

54. Add delivery mapping by week/sprint from these points.
   - Estimate: 25m
   - Done when: every point is assigned to a sequence window.

## Core Test Scenarios
- Register with unique email/username succeeds.
- Register with duplicate email or username fails.
- Login works with email and with username identifier.
- OAuth flow creates or links user by email.
- Refresh token rotation invalidates previous token.
- Buy fee math and net amount calculations are correct.
- Sell realized PnL calculation is correct.
- Price peak reset trigger executes on BUY insertion.
- Portfolio and opportunities are user-scoped.
- Alert acknowledge updates status and timestamps.
- Flyway migrations `V1..V4` apply cleanly.

## Assumptions
- OAuth provider for this scope is Google only.
- `ddl_scripts.sql` is the authoritative domain schema baseline.
- Out-of-scope for now: forgot/reset password flows.
- This is an MVP implementation sequence; production hardening can be a follow-up plan.
