# Portainer API Action

A reusable GitHub Action to deploy and manage Docker stacks via the Portainer API. This action simplifies deploying Docker Compose stacks to your Portainer instance as part of your CI/CD pipeline.

## Features

- 🚀 Deploy new stacks to Portainer
- 🔄 Update existing stacks
- 🔁 Redeploy stacks with image pulls
- 🌍 Support for environment variables
- 🧹 Optional service pruning
- 📦 Works with Docker Swarm stacks

## Prerequisites

- A running Portainer instance (v2.0+)
- Portainer API access token
- Docker Compose file defining your stack
- A Portainer endpoint running in **Docker Swarm** mode (this action uses the Swarm stack API)

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `portainer_url` | Portainer instance URL (e.g., `https://portainer.example.com`) | Yes | - |
| `portainer_api_key` | Portainer API access token | Yes | - |
| `stack_name` | Name of the stack to deploy/update | Yes | `${GITHUB_REPOSITORY#*/}` |
| `stack_file` | Path to docker-compose stack file | No | `docker-compose.yml` |
| `endpoint_id` | Portainer endpoint ID | No | `1` |
| `action` | Action to perform: `deploy`, `update`, or `redeploy` | No | `redeploy` |
| `env_vars` | Environment variables as JSON string | No | `{}` |
| `prune` | Prune services not defined in the stack file | No | `true` |

Notes:

- `stack_file` must exist in the workspace (use `actions/checkout@v4` if it’s in your repo).
- `endpoint_id` must be a number (as used by Portainer).
- `env_vars` must be valid JSON representing an object, e.g. `{ "KEY": "value" }`.
- `prune` should be `true` or `false`.

## Outputs

| Output | Description |
|--------|-------------|
| `stack_id` | ID of the deployed/updated stack |
| `status` | Status of the operation (`created`, `updated`, or `redeployed`) |

## Versioning / Tagging

This action supports both **immutable release tags** and a **moving major tag**:

- Prefer pinning to an immutable release for reproducible builds: `bignellrp/portainer-api-action@v1.0.0`
- Use the moving major tag to automatically receive compatible updates: `bignellrp/portainer-api-action@v1`

## Usage Examples

This repo includes working examples you can copy:

- Docker build + deploy workflow: [examples/docker-build.yml](examples/docker-build.yml)
- Example stack file: [examples/docker-compose.yml](examples/docker-compose.yml)
- Example image used by the workflow: [examples/Dockerfile](examples/Dockerfile)

### Basic Usage

```yaml
name: Deploy to Portainer

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy to Portainer
        uses: bignellrp/portainer-api-action@v1.0.0
        with:
          portainer_url: ${{ secrets.PORTAINER_URL }}
          portainer_api_key: ${{ secrets.PORTAINER_API_KEY }}
          stack_name: my-application
          action: redeploy
```

### Advanced Usage with Environment Variables

```yaml
name: Deploy to Portainer with Environment Variables

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy to Portainer
        uses: bignellrp/portainer-api-action@v1.0.0
        with:
          portainer_url: ${{ secrets.PORTAINER_URL }}
          portainer_api_key: ${{ secrets.PORTAINER_API_KEY }}
          stack_name: my-application
          stack_file: docker-compose.prod.yml
          endpoint_id: 2
          action: redeploy
          env_vars: |
            {
              "DATABASE_URL": "${{ secrets.DATABASE_URL }}",
              "API_KEY": "${{ secrets.API_KEY }}",
              "ENVIRONMENT": "production"
            }
          prune: true
```

### Docker Build and Deploy Workflow

```yaml
name: Build and Deploy

on:
  push:
    branches:
      - main

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
            file: backend/docker-compose.yml
          - name: database
            file: database/docker-compose.yml
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy ${{ matrix.stack.name }} to Portainer
        uses: bignellrp/portainer-api-action@v1.0.0
        with:
          portainer_url: ${{ secrets.PORTAINER_URL }}
          portainer_api_key: ${{ secrets.PORTAINER_API_KEY }}
          stack_name: ${{ matrix.stack.name }}
          stack_file: ${{ matrix.stack.file }}
```

## Setting Up Secrets

You'll need to configure the following secrets in your GitHub repository:

1. **PORTAINER_URL**: Your Portainer instance URL (e.g., `https://portainer.example.com`)
2. **PORTAINER_API_KEY**: Your Portainer API access token

Tip: you can also store the URL as a repository variable (e.g., `vars.PORTAINER_URL`) and the token as a secret (e.g., `secrets.PORTAINER_TOKEN`) as shown in [examples/docker-build.yml](examples/docker-build.yml).

### How to Get Portainer API Key

1. Log in to your Portainer instance
2. Go to **User settings** (click on your username in the top right)
3. Scroll down to **Access tokens**
4. Click **Add access token**
5. Give it a description and click **Create**
6. Copy the token (you won't be able to see it again!)

### Adding Secrets to GitHub

1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add `PORTAINER_URL` and `PORTAINER_API_KEY`

## Docker Compose File Example

```yaml
version: '3.8'

services:
  web:
    image: myusername/myapp:latest
    ports:
      - "80:8080"
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - API_KEY=${API_KEY}
    deploy:
      replicas: 2
      restart_policy:
        condition: on-failure
```

## Troubleshooting

### Stack Not Found

If the stack doesn't exist, the action will automatically create it. Make sure:
- The `stack_name` is correct
- You have permissions to create stacks in your Portainer instance

### Authentication Errors

- Verify your `PORTAINER_API_KEY` is correct and hasn't expired
- Ensure your `PORTAINER_URL` is correct and accessible from GitHub Actions runners

### Stack Update Failures

- Check that your `docker-compose.yml` file is valid
- Verify the endpoint ID is correct
- Ensure you have sufficient permissions in Portainer

## API Compatibility

This action is compatible with Portainer CE and Portainer BE version 2.0 and above, which includes the v2.0+ API.

It targets the **Docker Swarm stack** API endpoints.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Support

If you encounter any issues or have questions, please [open an issue](https://github.com/bignellrp/portainer-api-action/issues) on GitHub.
