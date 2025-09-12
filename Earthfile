VERSION 0.8

# Base image with Elixir and Erlang
FROM hexpm/elixir:1.16.0-erlang-26.2.2-debian-bookworm-20240130-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Set environment variables
ENV MIX_ENV=test

# deps target - Install Elixir dependencies
deps:
    # Copy mix files
    COPY mix.exs mix.lock ./
    
    # Install hex and rebar
    RUN mix local.hex --force && mix local.rebar --force
    
    # Install dependencies
    RUN mix deps.get
    
    # Cache dependencies
    SAVE ARTIFACT deps /deps
    SAVE ARTIFACT _build /build

# compile target - Compile the project
compile:
    FROM +deps
    
    # Copy source code
    COPY --dir lib config test ./
    
    # Compile with warnings as errors
    RUN mix compile --warnings-as-errors
    
    # Save compiled artifacts
    SAVE ARTIFACT _build /build
    SAVE ARTIFACT deps /deps

# format target - Check code formatting
format:
    FROM +deps
    
    # Copy source files needed for formatting check
    COPY --dir lib config test ./
    COPY .formatter.exs 2>/dev/null || echo "no .formatter.exs file"
    
    # Check formatting
    RUN mix format --check-formatted

# test target - Run tests
test:
    FROM +compile
    
    # Run tests
    RUN mix test

# ci target - Run all checks in sequence
ci:
    BUILD +deps
    BUILD +compile  
    BUILD +format
    BUILD +test
    
    # Optional: create a final artifact with all results
    FROM +test
    RUN echo "All CI checks passed successfully!"

# dev target - Setup for development
dev:
    FROM +deps
    
    # Copy all source code
    COPY . .
    
    # Compile in dev mode
    ENV MIX_ENV=dev
    RUN mix compile
    
    # Start an interactive shell
    CMD ["iex", "-S", "mix"]

# prod-compile target - Compile for production
prod-compile:
    FROM +deps
    
    # Set production environment
    ENV MIX_ENV=prod
    
    # Copy source code
    COPY --dir lib config ./
    
    # Compile for production
    RUN mix compile
    
    # Save production build
    SAVE ARTIFACT _build/prod /prod-build