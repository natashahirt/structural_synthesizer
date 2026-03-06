# Use official Julia image
FROM julia:1.12.4

# Set working directory
WORKDIR /app

# Copy Project.toml files first (for better layer caching)
COPY Project.toml Manifest.toml ./
COPY StructuralSynthesizer/Project.toml StructuralSynthesizer/
COPY StructuralSizer/Project.toml StructuralSizer/
COPY StructuralPlots/Project.toml StructuralPlots/
COPY external/Asap/Project.toml external/Asap/

# Note: Manifest.toml files are optional - Pkg.instantiate() will create them if needed

# Copy source code
COPY StructuralSynthesizer/src ./StructuralSynthesizer/src
COPY StructuralSizer/src ./StructuralSizer/src
COPY StructuralPlots/src ./StructuralPlots/src
COPY external/Asap/src ./external/Asap/src
COPY scripts/api ./scripts/api

# Fix Windows-style paths in Project.toml files to Linux-style
RUN sed -i 's|\\\\|/|g' StructuralSynthesizer/Project.toml StructuralSizer/Project.toml

# Install dependencies (skip precompilation - GLMakie requires display server)
RUN julia --project=StructuralSynthesizer -e 'using Pkg; Pkg.instantiate()'

# Expose port (AWS App Runner sets PORT env var)
EXPOSE 8080

# Set environment variables
ENV JULIA_PROJECT=StructuralSynthesizer
ENV SIZER_HOST=0.0.0.0

# Start the server
CMD ["julia", "--project=StructuralSynthesizer", "scripts/api/sizer_service.jl"]
