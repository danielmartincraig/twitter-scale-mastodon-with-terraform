# twitter-scale-mastodon

![Home timeline](images/home-timeline-screenshot.png)

This project is a production-ready implementation of a Mastodon instance that scales to Twitter-scale (500M users, 700 average fanout, unbalanced social graph, 7k posts / second). It's only 10k lines of code and can easily be adapted into any Twitter-like social network. It shares no code with the [official Mastodon implementation](https://github.com/mastodon/mastodon).

The implementation is built on top of [Rama](https://redplanetlabs.com/), a new programming platform that enables end-to-end scalable backends to be built in their entirety in 100x less code than otherwise. Rama is a generic platform for building any application backend, not just social networks. This project is a demonstration of Rama's power. Rama can be downloaded [on our website](https://redplanetlabs.com/download).

We ran this code on a public instance available for anyone to use from August 15th, 2023 to August 24th, 2023. To demonstrate its scale, we ran the instance with 100M bots posting 3,500 times per second at 403 average fanout. The social graph was extremely unbalanced, with the largest user having 22M followers. During its lifetime the instance processed 2.66B posts and made 1.07T timeline deliveries.

Here's a chart showing the scalability of the implementation:

![Scalability](images/scalability.png)

You can read a deep-dive exploration of how this instance is implemented in [this blog post](https://blog.redplanetlabs.com/2023/08/15/how-we-reduced-the-cost-of-building-twitter-at-twitter-scale-by-100x/). That post also includes other performance charts.

## Implementation overview

The implementation is structured like this:

![Structure](images/overall-structure.png)

The Mastodon backend is implemented as Rama modules, which handle all the data processing, data indexing, and most of the product logic. On top of that is the implementation of the [Mastodon API](https://docs.joinmastodon.org/api/) using Spring/Reactor. For the most part, the API implementation just handles HTTP requests with simple calls to the Rama modules and serves responses as JSON.

[S3](https://aws.amazon.com/s3/) is used only for serving pictures and videos. Though we could serve those from Rama, static content like that is better served via a [CDN](https://en.wikipedia.org/wiki/Content_delivery_network). So we chose to use S3 to mimic that sort of architecture. All other storage is handled by the Rama modules.

The backend is implemented in the [backend/](backend) folder and contains six modules:

- [Relationships](backend/src/main/java/com/rpl/mastodon/modules/Relationships.java): Implements the social graph, follow suggestions, and other relationships between entities.
- [Core](backend/src/main/java/com/rpl/mastodon/modules/Core.java): Implements timelines, profiles, fanout, boosts, favorites, conversations, replies, and the other core parts of the product.
- [Notifications](backend/src/main/java/com/rpl/mastodon/modules/Notifications.java): Implements notification timelines, including favorites/boosts, mentions, poll completion, new followers, and others.
- [TrendsAndHashtags](backend/src/main/java/com/rpl/mastodon/modules/TrendsAndHashtags.java): Implements trending statuses, links, and hashtags, as well as hashtag timelines and other hashtag-oriented features.
- [GlobalTimelines](backend/src/main/java/com/rpl/mastodon/modules/GlobalTimelines.java): Implements local and federated timelines of all statuses.
- [Search](backend/src/main/java/com/rpl/mastodon/modules/Search.java): Implements profile, status, and hashtag search, as well as profile directories.

The API server is implemented in the [api/](api) folder.

Federation is implemented in both the API server and the [Core](backend/src/main/java/com/rpl/mastodon/modules/Core.java) module.

## Running locally

Running the instance locally is easy. We've set up the API server to also be able run an in process cluster with all the modules launched. All you have to do is run this from the `api/` folder:

```
mvn spring-boot:run
```

Since this doesn't configure credentials to connect to S3, you'll see an error about that. That error is ignored and the instance will continue launching. The launch is finished when the Spring logo prints to the console (may take a few minutes).

If you look at [MastodonApiApplication](api/src/main/java/com/rpl/mastodonapi/MastodonApiApplication.java), you can see how it also adds some data to the modules. These include users "alice", "bob", and "charlie" with passwords "alice", "bob", and "charlie" respectively.

To run the frontend, you'll need to run [our fork of Soapbox](https://github.com/redplanetlabs/soapbox). Our fork contains minor tweaks to the official implementation to fix a variety of small issues. From the root of that fork run:

```
yarn install --frozen-lockfile
NODE_ENV="development" BACKEND_URL="http://localhost:8080" yarn build
NODE_ENV="development" BACKEND_URL="http://localhost:8080" yarn dev --port 8000
```

Once everything finishes launching, you can play with the instance at [http://localhost:8000](http://localhost:8000).

Note that the instance can be run locally on macOS or Linux, but it doesn't currently work on Windows.

## Running on a real cluster

Modules should be deployed in this order:

- Relationships
- Core
- GlobalTimelines
- TrendsAndHashtags
- Notifications
- Search

## Accessing the Cluster UI

The Rama Conductor serves a web-based Cluster UI on port 8888. Rather than opening that port to the internet, use AWS SSM port forwarding to access it securely from your local machine — no open inbound rules or SSH key required.

First, find the instance ID from the Terraform outputs or the AWS console:

```bash
cd terraform
terraform output zookeeper_instance_ids
```

Then start the port forwarding session:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'
```

Keep that terminal open and navigate to [http://localhost:8888](http://localhost:8888) in your browser.

The [AWS Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) must be installed locally for this to work. The EC2 instance also needs the SSM agent running and an IAM instance profile with `AmazonSSMManagedInstanceCore` permissions, both of which are configured by this project's Terraform.

## CI/CD and Deployment

This project includes a complete CI/CD pipeline using GitHub Actions and Terraform for automated deployment to AWS EC2.

### Documentation

- [Secrets Configuration](docs/SECRETS_CONFIGURATION.md) - How to configure GitHub Actions secrets and AWS credentials
- [Terraform Variables](docs/TERRAFORM_VARIABLES.md) - All configurable Terraform parameters and examples
- [Terraform Documentation](terraform/README.md) - Infrastructure as code configuration and usage
- [Deployment Scripts](scripts/README-deploy.md) - Application deployment and configuration scripts
- [Deployment Runbook](docs/DEPLOYMENT_RUNBOOK.md) - Troubleshooting, health checks, and emergency procedures
- [Rollback and Cleanup](docs/ROLLBACK_AND_CLEANUP.md) - How to rollback deployments and destroy infrastructure
- [Error Handling](docs/ERROR_HANDLING.md) - Common errors and resolution strategies

### Quick Start

1. Configure required GitHub Actions secrets (see [Secrets Configuration](docs/SECRETS_CONFIGURATION.md))
2. Configure Terraform variables for your environment (see [Terraform Variables](docs/TERRAFORM_VARIABLES.md))
3. Push code to trigger the CI/CD pipeline
4. Monitor deployment in the Actions tab
5. Access your deployed instance at the API endpoint shown in deployment summary

### Workflow Triggers

The CI/CD pipeline automatically triggers based on Git events:

#### Automatic Triggers

- **All branches and pull requests**: Runs build and test jobs
  - Compiles both backend and API modules
  - Executes unit tests
  - Packages JAR artifacts
  - Does NOT deploy to any environment

- **Main branch pushes**: Deploys to staging environment
  - Runs full build and test pipeline
  - Provisions/updates staging infrastructure via Terraform
  - Deploys applications to staging EC2 instances
  - Runs health checks

- **Release tags** (v*.*.* or release-*): Deploys to production environment
  - Runs full build and test pipeline
  - Provisions/updates production infrastructure via Terraform
  - Deploys applications to production EC2 instances
  - Runs health checks
  - Creates deployment summary

#### Manual Triggers

Use the GitHub Actions UI to manually trigger deployments:

1. Go to **Actions** tab in GitHub
2. Select **CI/CD Pipeline** workflow
3. Click **Run workflow** button
4. Choose options:
   - **Branch**: Select branch to deploy from
   - **Environment**: staging or production
   - **Action**: deploy or rollback
   - **Artifact Version** (for rollback): Git commit SHA of version to restore

### Monitoring Workflow Execution

#### Via GitHub Actions UI

1. Navigate to the **Actions** tab in your repository
2. Click on the workflow run you want to monitor
3. View real-time logs for each job:
   - **build-backend**: Backend module compilation
   - **build-api**: API module compilation
   - **test-backend**: Backend unit tests
   - **test-api**: API unit tests
   - **package-backend**: Backend JAR creation
   - **package-api**: API JAR creation
   - **deploy**: Infrastructure provisioning and application deployment

4. Check job status indicators:
   - 🟡 Yellow: Job in progress
   - ✅ Green: Job succeeded
   - ❌ Red: Job failed
   - ⚪ Gray: Job queued or skipped

#### Deployment Summary

After successful deployment, view the deployment summary:

1. Click on the **deploy** job
2. Scroll to the bottom of the logs
3. Find the **Deployment Summary** section containing:
   - Deployed artifact versions (Git commit SHA)
   - Zookeeper cluster node IPs
   - API instance public IP
   - API endpoint URL (http://IP:8080)
   - Zookeeper connection string
   - Health check results

#### Downloading Artifacts

To download built JAR files:

1. Go to the workflow run summary page
2. Scroll to **Artifacts** section at the bottom
3. Download:
   - `mastodon-backend-jar`: Backend module JAR
   - `mastodon-api-jar`: API module JAR
   - `deployment-summary`: Deployment details (if deployed)

### Required GitHub Actions Secrets

Configure these secrets in **Settings → Secrets and variables → Actions**:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key for Terraform | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key for Terraform | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_DEFAULT_REGION` | AWS region for deployment | `us-east-1` |
| `TF_CLOUD_TOKEN` | Terraform Cloud API token | `xxxxxx.atlasv1.zzzzz` |
| `TF_CLOUD_ORGANIZATION` | Terraform Cloud organization name | `my-company` |
| `TF_CLOUD_WORKSPACE` | Terraform Cloud workspace name | `mastodon-deployment` |
| `SSH_PRIVATE_KEY` | SSH private key for EC2 access | `-----BEGIN RSA PRIVATE KEY-----...` |

See [Secrets Configuration](docs/SECRETS_CONFIGURATION.md) for detailed setup instructions.

### Manual Deployment Process

To manually deploy without triggering the workflow:

1. **Build locally**:
   ```bash
   cd backend && mvn clean package
   cd ../api && mvn clean package
   ```

2. **Provision infrastructure**:
   ```bash
   cd terraform
   terraform init
   terraform plan -var-file=environments/staging.tfvars
   terraform apply -var-file=environments/staging.tfvars
   ```

3. **Deploy applications**:
   ```bash
   cd ../scripts
   ./configure-zookeeper.sh <zk-ip-1> <zk-ip-2> <zk-ip-3>
   ./deploy-application.sh
   ```

4. **Verify health**:
   ```bash
   ./health-check.sh
   ```

### Rollback Procedures

#### Automated Rollback via Workflow

1. Go to **Actions** → **CI/CD Pipeline** → **Run workflow**
2. Select:
   - **Action**: rollback
   - **Environment**: staging or production
   - **Artifact Version**: Git commit SHA to restore (e.g., `abc123def`)
3. Click **Run workflow**
4. Monitor rollback execution in Actions tab

#### Manual Rollback

1. **Identify target version**:
   ```bash
   # List recent deployments
   git log --oneline -10
   ```

2. **Download artifacts** from the target workflow run in GitHub Actions

3. **Deploy previous version**:
   ```bash
   cd scripts
   ./deploy-application.sh --backend-jar=/path/to/old/backend.jar \
                           --api-jar=/path/to/old/api.jar
   ```

4. **Verify health**:
   ```bash
   ./health-check.sh
   ```

#### Infrastructure Rollback

If infrastructure changes caused issues:

1. **Review Terraform state**:
   ```bash
   cd terraform
   terraform show
   ```

2. **Revert to previous configuration**:
   ```bash
   git checkout <previous-commit>
   terraform plan -var-file=environments/staging.tfvars
   terraform apply -var-file=environments/staging.tfvars
   ```

3. **Or destroy and recreate**:
   ```bash
   terraform destroy -var-file=environments/staging.tfvars
   # Fix configuration
   terraform apply -var-file=environments/staging.tfvars
   ```

See [Rollback and Cleanup](docs/ROLLBACK_AND_CLEANUP.md) for detailed procedures.

### Troubleshooting

For common issues and solutions, see:
- [Deployment Runbook](docs/DEPLOYMENT_RUNBOOK.md) - Troubleshooting guide
- [Error Handling](docs/ERROR_HANDLING.md) - Error scenarios and resolutions

Quick troubleshooting steps:

1. **Build failures**: Check Maven logs in build job output
2. **Test failures**: Download test reports from artifacts
3. **Terraform errors**: Review terraform plan output and state
4. **Deployment failures**: Check SSH connectivity and security groups
5. **Health check failures**: Verify services are running on EC2 instances

For detailed deployment procedures, troubleshooting, and rollback instructions, see the documentation links above.

