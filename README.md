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

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `portainer_url` | Portainer instance URL (e.g., `https://portainer.example.com`) | Yes | - |
| `portainer_api_key` | Portainer API access token | Yes | - |
| `stack_name` | Name of the stack to deploy/update | Yes | - |
| `stack_file` | Path to docker-compose stack file | No | `docker-compose.yml` |
| `endpoint_id` | Portainer endpoint ID | No | `1` |
| `action` | Action to perform: `deploy`, `update`, or `redeploy` | No | `update` |
| `env_vars` | Environment variables as JSON string | No | `{}` |
| `prune` | Prune services not defined in the stack file | No | `true` |

## Outputs

| Output | Description |
|--------|-------------|
| `stack_id` | ID of the deployed/updated stack |
| `status` | Status of the operation (`created`, `updated`, or `redeployed`) |

## Usage Examples

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
        uses: bignellrp/portainer-api-action@v1
        with:
          portainer_url: ${{ secrets.PORTAINER_URL }}
          portainer_api_key: ${{ secrets.PORTAINER_API_KEY }}
          stack_name: my-application
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
        uses: bignellrp/portainer-api-action@v1
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

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ secrets.DOCKERHUB_USERNAME }}/myapp:latest

      - name: Deploy to Portainer
        uses: bignellrp/portainer-api-action@v1
        with:
          portainer_url: ${{ secrets.PORTAINER_URL }}
          portainer_api_key: ${{ secrets.PORTAINER_API_KEY }}
          stack_name: my-application
          action: redeploy
```

### Multiple Stacks Deployment

```yaml
name: Deploy Multiple Stacks

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        stack:
          - name: frontend
            file: frontend/docker-compose.yml
          - name: backend
            file: backend/docker-compose.yml
          - name: database
            file: database/docker-compose.yml
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy ${{ matrix.stack.name }} to Portainer
        uses: bignellrp/portainer-api-action@v1
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

This action is compatible with Portainer API v2.0 and above.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Support

If you encounter any issues or have questions, please [open an issue](https://github.com/bignellrp/portainer-api-action/issues) on GitHub.
