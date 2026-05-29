#!/bin/bash
# Zookeeper bootstrap script
# Installs Java 8 and Apache Zookeeper
# Validates: Requirements 7.1, 7.4

set -e

# Wait for instance metadata service to confirm IAM credentials are available
# (needed before any aws cli calls, including S3 downloads)
# Uses IMDSv2: a PUT request first obtains a session token, then the token
# is used to query the credentials endpoint.
echo "Waiting for IAM instance profile credentials..."
until TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
      --connect-timeout 2) && \
    curl -sf --connect-timeout 2 \
      -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/iam/security-credentials/ > /dev/null; do
  echo "IAM credentials not yet available, retrying in 5 seconds..."
  sleep 5
done
echo "IAM credentials available, proceeding..."

# Wait for NAT Gateway / internet connectivity
echo "Waiting for internet connectivity..."
while ! curl -s --connect-timeout 5 https://yum.corretto.aws/ > /dev/null; do
  echo "Internet not available, waiting 10 seconds..."
  sleep 10
done
echo "Internet is available, proceeding..."

# Update system packages
yum update -y

# Install Java 8 (Amazon Corretto)
rpm --import https://yum.corretto.aws/corretto.key
curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
yum install -y java-1.8.0-amazon-corretto java-1.8.0-amazon-corretto-devel

# Set JAVA_HOME
echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0-amazon-corretto" >> /etc/profile.d/java.sh
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /etc/profile.d/java.sh
source /etc/profile.d/java.sh

# Download and install Apache Zookeeper
ZOOKEEPER_VERSION="3.8.3"
ZOOKEEPER_DIR="/opt/zookeeper"
ZOOKEEPER_DOWNLOAD_URL="https://archive.apache.org/dist/zookeeper/zookeeper-$${ZOOKEEPER_VERSION}/apache-zookeeper-$${ZOOKEEPER_VERSION}-bin.tar.gz"

# Create installation directory
mkdir -p $ZOOKEEPER_DIR
cd /tmp

# Download Zookeeper
wget -q $ZOOKEEPER_DOWNLOAD_URL -O zookeeper.tar.gz

# Extract Zookeeper
tar -xzf zookeeper.tar.gz -C $ZOOKEEPER_DIR --strip-components=1

# Clean up download
rm -f zookeeper.tar.gz

# Create Zookeeper data directory with correct permissions
mkdir -p /var/lib/zookeeper
chown -R root:root /var/lib/zookeeper
chmod 755 /var/lib/zookeeper

# Create Zookeeper log directory
mkdir -p /var/log/zookeeper
chown -R root:root /var/log/zookeeper
chmod 755 /var/log/zookeeper

# Create server ID file
echo "${server_id}" > /var/lib/zookeeper/myid

# Create basic zoo.cfg template
cat > $ZOOKEEPER_DIR/conf/zoo.cfg << 'EOF'
${zookeeper_config}
EOF

# Create systemd service file for Zookeeper
cat > /etc/systemd/system/zookeeper.service << 'EOF'
${zookeeper_service_unit}
EOF

# Reload systemd to recognize new service
systemctl daemon-reload

# Enable Zookeeper service (but don't start yet - will be started after cluster configuration)
systemctl enable zookeeper

# Install CloudWatch Logs agent (optional)
echo "Installing CloudWatch Logs agent..."
yum install -y amazon-cloudwatch-agent

# Configure CloudWatch Logs agent for Zookeeper logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/zookeeper/*.log",
            "log_group_name": "/aws/ec2/mastodon/zookeeper",
            "log_stream_name": "{instance_id}/zookeeper",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/mastodon/*.log",
            "log_group_name": "/aws/ec2/mastodon/backend",
            "log_stream_name": "{instance_id}/backend",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWEOF

# Start CloudWatch Logs agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Enable CloudWatch agent to start on boot
systemctl enable amazon-cloudwatch-agent

echo "CloudWatch Logs agent configured and started"

# Ensure SSM agent is running (pre-installed on AL2 but not always started)
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Download Rama runtime from S3
# The binary is large (~17 GB); S3 within the same region avoids internet routing
# and provides much higher throughput than a public wget.
RAMA_INSTALL_DIR="/opt/rama"
mkdir -p "$RAMA_INSTALL_DIR"

echo "Downloading Rama runtime from s3://${deploy_bucket}/${rama_s3_key} ..."
aws s3 cp "s3://${deploy_bucket}/${rama_s3_key}" "$RAMA_INSTALL_DIR/rama.zip" \
  --region "${aws_region}" \
  --no-progress

echo "Extracting Rama runtime..."
unzip -q "$RAMA_INSTALL_DIR/rama.zip" -d "$RAMA_INSTALL_DIR"
rm -f "$RAMA_INSTALL_DIR/rama.zip"

# Make Rama CLI executable
chmod +x "$RAMA_INSTALL_DIR/rama"

# Create Rama log and local-data directories
mkdir -p "$RAMA_INSTALL_DIR/logs"
mkdir -p /data/rama

# Write rama.yaml — Conductor configuration.
# Zookeeper is running on this same instance, so we point at localhost.
# zookeeper.port must match zoo.cfg clientPort (2181); Rama's default is 2000.
cat > "$RAMA_INSTALL_DIR/rama.yaml" << 'EOF'
${rama_config}
EOF

# Install the Rama Conductor systemd service
cat > /etc/systemd/system/rama-conductor.service << 'EOF'
${rama_conductor_service_unit}
EOF

# Install the Rama Supervisor systemd service
cat > /etc/systemd/system/rama-supervisor.service << 'EOF'
${rama_supervisor_service_unit}
EOF

# Reload systemd, enable and start Zookeeper first, then the Conductor and the supervisor
systemctl daemon-reload
systemctl enable rama-conductor
systemctl enable rama-supervisor

# Start Zookeeper first and wait for it to bind its client port (2181)
systemctl start zookeeper
echo "Waiting for Zookeeper to be ready on port 2181..."
until (echo > /dev/tcp/127.0.0.1/2181) 2>/dev/null; do
  sleep 2
done
echo "Zookeeper is ready."

# Start the Conductor and wait for it to be ready on its Thrift port (1973)
systemctl start rama-conductor
echo "Waiting for Rama Conductor to be ready on port 1973..."
until (echo > /dev/tcp/127.0.0.1/1973) 2>/dev/null; do
  sleep 5
done
echo "Rama Conductor is ready."

# Start the Supervisor only after the Conductor is confirmed up
systemctl start rama-supervisor

# Wait for the Supervisor to reach active (running) state before deploying modules
echo "Waiting for Rama Supervisor to be active..."
until systemctl is-active --quiet rama-supervisor; do
  sleep 5
done
echo "Rama Supervisor is active."

# Give the Supervisor time to finish registering with the Conductor before deploying
echo "Waiting for Supervisor to register with Conductor..."
sleep 30
echo "Proceeding with module deploy."

echo "Rama runtime installed and Conductor and Supervisor services registered" >> /var/log/zookeeper/bootstrap.log

# Log installation completion
echo "Zookeeper installation completed successfully" >> /var/log/zookeeper/bootstrap.log
echo "Server ID: ${server_id}" >> /var/log/zookeeper/bootstrap.log

# Deploy the monitoring system module now that all daemons are confirmed ready
/opt/rama/rama deploy \
  --action launch \
  --systemModule monitoring \
  --tasks 16 \
  --threads 4 \
  --workers 2 \
  --replicationFactor 1

# Download application JARs built from this commit
# Backend JAR contains the Rama modules (Relationships, Core, GlobalTimelines, etc.)
# and will be deployed to the cluster via: /opt/rama/rama deploy --action launch --jar ...
# API JAR goes under /opt/mastodon-api where its systemd service will launch it
echo "Downloading application JARs for commit ${git_sha} ..."

mkdir -p /opt/rama/modules
aws s3 cp \
  "s3://${deploy_bucket}/jars/backend/${git_sha}/mastodon-jar-with-dependencies.jar" \
  /opt/rama/modules/mastodon-jar-with-dependencies.jar \
  --region "${aws_region}" \
  --no-progress

mkdir -p /opt/mastodon-api
aws s3 cp \
  "s3://${deploy_bucket}/jars/api/${git_sha}/mastodonapi.jar" \
  /opt/mastodon-api/mastodonapi.jar \
  --region "${aws_region}" \
  --no-progress

echo "Application JARs downloaded successfully." >> /var/log/zookeeper/bootstrap.log

# Deploy Mastodon backend modules in dependency order.
# Each module is polled for :running status before the next is deployed,
# since later modules depend on PStates from earlier ones.
# See: https://blog.redplanetlabs.com/2023/08/15/how-we-reduced-the-cost-of-building-twitter-at-twitter-scale-by-100x/

BACKEND_JAR=/opt/rama/modules/mastodon-jar-with-dependencies.jar
DEPLOY_ARGS="--action launch --jar $BACKEND_JAR --tasks 16 --threads 4 --workers 1 --replicationFactor 1"

wait_for_module() {
  local module=$1
  echo "Waiting for module $module to reach RUNNING status..."
  while true; do
    # Run moduleStatus in a subshell so a non-zero exit (module not yet
    # registered) does not trigger set -e and abort the bootstrap script.
    status=$(/opt/rama/rama moduleStatus "$module" 2>/dev/null || true)
    if echo "$status" | grep -q '"moduleState":"RUNNING"'; then
      break
    fi
    sleep 10
  done
  echo "Module $module is running."
}

echo "Deploying Relationships module..."
/opt/rama/rama deploy $DEPLOY_ARGS --module com.rpl.mastodon.modules.Relationships
wait_for_module com.rpl.mastodon.modules.Relationships

echo "Deploying Core module..."
/opt/rama/rama deploy $DEPLOY_ARGS --module com.rpl.mastodon.modules.Core
wait_for_module com.rpl.mastodon.modules.Core

echo "Deploying GlobalTimelines module..."
/opt/rama/rama deploy $DEPLOY_ARGS --module com.rpl.mastodon.modules.GlobalTimelines
wait_for_module com.rpl.mastodon.modules.GlobalTimelines

echo "Deploying TrendsAndHashtags module..."
/opt/rama/rama deploy $DEPLOY_ARGS --module com.rpl.mastodon.modules.TrendsAndHashtags
wait_for_module com.rpl.mastodon.modules.TrendsAndHashtags

echo "Deploying Notifications module..."
/opt/rama/rama deploy $DEPLOY_ARGS --module com.rpl.mastodon.modules.Notifications
wait_for_module com.rpl.mastodon.modules.Notifications

echo "Deploying Search module..."
/opt/rama/rama deploy $DEPLOY_ARGS --module com.rpl.mastodon.modules.Search
wait_for_module com.rpl.mastodon.modules.Search

echo "All Mastodon modules deployed successfully." >> /var/log/zookeeper/bootstrap.log

# Verify all modules are RUNNING before starting the API, since the API
# connects to all modules on startup and will crash if any are not yet alive.
wait_for_module com.rpl.mastodon.modules.Relationships
wait_for_module com.rpl.mastodon.modules.Core
wait_for_module com.rpl.mastodon.modules.GlobalTimelines
wait_for_module com.rpl.mastodon.modules.TrendsAndHashtags
wait_for_module com.rpl.mastodon.modules.Notifications
wait_for_module com.rpl.mastodon.modules.Search
echo "All modules confirmed RUNNING, starting API." >> /var/log/zookeeper/bootstrap.log

# Install the Mastodon API systemd service
cat > /etc/systemd/system/mastodon-api.service << 'EOF'
${mastodon_api_service_unit}
EOF

# Create API log directory
mkdir -p /opt/mastodon-api/logs

systemctl daemon-reload
systemctl enable mastodon-api
systemctl start mastodon-api

echo "Mastodon API service started." >> /var/log/zookeeper/bootstrap.log