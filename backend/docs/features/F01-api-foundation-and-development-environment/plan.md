# Implementation Plan: API Foundation and Development Environment

**Prerequisites:**
- Elixir 1.20.1 and Erlang/OTP 29 available locally (already installed)
- Docker and Docker Compose v2 for the container path
- PostgreSQL 16 reachable through `docker-compose.dev.yml` (development, host port 54320) and `docker-compose.test.yml` (test, host port 54321)
- New dependencies to be added: `cors_plug`, `ex_machina` (test only), `excoveralls` (test only)
- Dependencies to be removed: `swoosh`, `gettext`, `req`, `dns_cluster` — none has a call site in this project
- Dependencies already present but currently unwired: `boundary`, `credo` (with the `ExSlop` plugin in `.credo.exs`)
- `phoenix_live_dashboard` stays as a dev-only diagnostic, which keeps `phoenix_live_view` as a transitive dependency
- Environment variables introduced by this feature: `DATABASE_URL`, `SECRET_KEY_BASE`, `JWT_SECRET`, `PORT`, `BIND_IP`, `CORS_ORIGINS`

---

### Stage 1: Project and Configuration Baseline

**1. Mix Project Definition** - Raise the declared Elixir version to match the required constraint, add the new dependencies for CORS, test factories and coverage reporting, and drop the four generator dependencies the service never calls. Wire the boundary compiler and the coverage tool into the project configuration, and expand the `precommit` alias into the full quality gate described in the spec.

**2. Scaffold Artefact Removal** - Delete the mailer module, the Gettext backend and its translation catalogues, and the static asset directory, along with every configuration line and router entry that referenced them across the environment config files. Remove the clustering child spec from the supervision tree. The spec lists each path and its reason.

**3. Compile-Time Configuration** - Update the shared application configuration so generated schemas use microsecond-precision timestamps alongside the existing UUID setting. Confirm the error rendering configuration still points at the JSON error view that Stage 3 rewrites.

**4. Runtime Environment Configuration** - Rewrite the runtime configuration so it serves every environment rather than production alone, reading the server port, bind address, CORS origins and database URL from the environment with sensible local fallbacks. Add the fail-fast guard that aborts boot with an explicit message when a required secret is absent outside the test environment.

**5. Environment Variable Documentation** - Create the example environment file listing every variable the application reads, each with a working default for local use, so a reviewer can copy it and start without hunting through configuration files.

### Stage 2: API-Only Conversion

**6. Endpoint Pipeline** - Strip the browser-oriented plugs from the endpoint so the service carries no cookie, session or static-asset overhead, and restrict body parsing to JSON only. Keep the LiveView socket and session plug available exclusively under the existing development routes flag so the LiveDashboard diagnostic survives the conversion. Insert the CORS plug ahead of the router.

**7. Web Entrypoint Macros** - Narrow the controller macro to the JSON format only and drop the static-asset references from the verified routes helper. Declare the web layer's architectural boundary as depending on the domain layer.

**8. Router and Pipelines** - Define the JSON-only API pipeline, register the health route, and add a catch-all route so any unmatched path produces the standard JSON error response instead of an HTML error page. Preserve the development-only diagnostic scope.

**9. Domain Boundary Declaration** - Declare the domain layer's architectural boundary with an explicit export list, establishing the one-way dependency rule that later contexts will extend as they are introduced.

### Stage 3: Error Contract and Health Endpoint

**10. Error Envelope Rendering** - Rewrite the JSON error view so every endpoint-level failure produces the single documented envelope, mapping each HTTP status to its machine code and human message, and special-casing the JSON parse failure. Ensure no failure path can leak internal exception detail into a response body.

**11. Changeset Error Rendering** - Add the view responsible for translating changeset failures into the envelope's per-field error map, so validation responses across every later feature share one shape.

**12. Fallback Controller** - Add the fallback controller that translates the domain error tuples listed in the spec into their HTTP statuses and envelopes, so no controller written from the next feature onward contains error rendering logic.

**13. Catch-All Error Action** - Add the controller action the catch-all route delegates to, producing the not-found envelope for any unmatched path.

**14. Database Health Check** - Add the domain function that verifies database connectivity with a real round trip and returns a value rather than raising when the connection is unavailable. Expose it through the health controller and its view, rendering the merged success and failure bodies defined in the spec.

### Stage 4: Data Layer Conventions and Environment

**15. Shared Schema Conventions** - Add the shared schema macro that fixes the primary key type, foreign key type and timestamp precision for every schema the later features introduce, so the conventions are declared once rather than repeated per module.

**16. Extensions Migration** - Generate the migration that enables the PostgreSQL extensions later features depend on, written reversibly so a rollback on a clean database succeeds.

**17. Container Image** - Write the multi-stage Dockerfile that compiles dependencies in a cache-friendly layer order and produces the runtime image, together with the build-context exclusion file. The image runs in development mode for the reasons recorded in the spec's decisions.

**18. Development Orchestration** - Add a readiness healthcheck to the existing development database service and add the API service that waits for it, applies the database setup and starts the server on the documented port. The test compose file stays database-only.

**19. Test Harness** - Add the channel case template and the factory module, and wire the factory into the existing data and connection case templates so every later feature inherits a consistent way to build test data. Add the JSON request helper the controller tests will use.

**20. Foundation Test Suite** - Cover the health endpoint, the error envelope across the endpoint-level failure paths, the CORS configuration and the schema conventions, as detailed in the spec's testing strategy.

**21. Quality Gate Verification** - Run the full `precommit` chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until the gate passes cleanly. Confirm the boundary compiler reports no violations.

**22. Minimal Run Documentation** - Update the README with prerequisites, the one-command container startup, the native setup path and the environment variable table, leaving the design-decision and seeded-credential sections to the documentation feature.
