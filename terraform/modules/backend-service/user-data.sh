#!/bin/bash
# Bootstrap script for Mastodon backend service nodes.
#
# Kept intentionally minimal to stay within EC2's 16 KB user_data limit.
# All config files (systemd units, zoo.cfg, rama.yaml, nginx conf) are
# fetched from S3 at boot rather than inlined here.

set -e

LOG=/var/log/bootstrap.log
exec > >(tee -a "$LOG") 2>&1

# ---------------------------------------------------------------------------
# 1. Wait for IMDSv2 credentials
# ---------------------------------------------------------------------------
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
echo "IAM credentials available."

# ---------------------------------------------------------------------------
# 2. Wait for internet connectivity
# ---------------------------------------------------------------------------
echo "Waiting for internet connectivity..."
while ! curl -s --connect-timeout 5 https://yum.corretto.aws/ > /dev/null; do
  echo "Internet not available, waiting 10 seconds..."
  sleep 10
done
echo "Internet is available."

# ---------------------------------------------------------------------------
# 3. System packages
# ---------------------------------------------------------------------------
yum update -y

# Java 8 (Amazon Corretto)
rpm --import https://yum.corretto.aws/corretto.key
curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
yum install -y java-1.8.0-amazon-corretto java-1.8.0-amazon-corretto-devel

echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0-amazon-corretto" >> /etc/profile.d/java.sh
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /etc/profile.d/java.sh
source /etc/profile.d/java.sh

# ---------------------------------------------------------------------------
# 4. Download all config files from S3
# ---------------------------------------------------------------------------
CONFIG_PREFIX="s3://${deploy_bucket}/config/${git_sha}"
echo "Downloading config files from $CONFIG_PREFIX ..."

aws s3 cp "$CONFIG_PREFIX/zoo.cfg"                    /tmp/zoo.cfg                    --region "${aws_region}" --no-progress
aws s3 cp "$CONFIG_PREFIX/rama.yaml"                  /tmp/rama.yaml                  --region "${aws_region}" --no-progress
aws s3 cp "$CONFIG_PREFIX/zookeeper.service"          /tmp/zookeeper.service          --region "${aws_region}" --no-progress
aws s3 cp "$CONFIG_PREFIX/rama-conductor.service"     /tmp/rama-conductor.service     --region "${aws_region}" --no-progress
aws s3 cp "$CONFIG_PREFIX/rama-supervisor.service"    /tmp/rama-supervisor.service    --region "${aws_region}" --no-progress
aws s3 cp "$CONFIG_PREFIX/mastodon-api.service"       /tmp/mastodon-api.service       --region "${aws_region}" --no-progress
aws s3 cp "$CONFIG_PREFIX/nginx-soapbox.conf"         /tmp/nginx-soapbox.conf         --region "${aws_region}" --no-progress

echo "Config files downloaded."

# ---------------------------------------------------------------------------
# 5. Zookeeper
# ---------------------------------------------------------------------------
ZOOKEEPER_VERSION="3.8.3"
ZOOKEEPER_DIR="/opt/zookeeper"
mkdir -p "$ZOOKEEPER_DIR" /var/lib/zookeeper /var/log/zookeeper

wget -q "https://archive.apache.org/dist/zookeeper/zookeeper-$${ZOOKEEPER_VERSION}/apache-zookeeper-$${ZOOKEEPER_VERSION}-bin.tar.gz" \
     -O /tmp/zookeeper.tar.gz
tar -xzf /tmp/zookeeper.tar.gz -C "$ZOOKEEPER_DIR" --strip-components=1
rm -f /tmp/zookeeper.tar.gz

echo "${server_id}" > /var/lib/zookeeper/myid
cp /tmp/zoo.cfg "$ZOOKEEPER_DIR/conf/zoo.cfg"
cp /tmp/zookeeper.service /etc/systemd/system/zookeeper.service

# ---------------------------------------------------------------------------
# 6. CloudWatch agent
# ---------------------------------------------------------------------------
yum install -y amazon-cloudwatch-agent

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
          },
          {
            "file_path": "/var/log/bootstrap.log",
            "log_group_name": "/aws/ec2/mastodon/bootstrap",
            "log_stream_name": "{instance_id}/bootstrap",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl enable amazon-cloudwatch-agent

# SSM agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# ---------------------------------------------------------------------------
# 7. Rama runtime
# ---------------------------------------------------------------------------
RAMA_INSTALL_DIR="/opt/rama"
mkdir -p "$RAMA_INSTALL_DIR" "$RAMA_INSTALL_DIR/logs" /data/rama

echo "Downloading Rama runtime from s3://${deploy_bucket}/${rama_s3_key} ..."
aws s3 cp "s3://${deploy_bucket}/${rama_s3_key}" "$RAMA_INSTALL_DIR/rama.zip" \
  --region "${aws_region}" --no-progress
unzip -q "$RAMA_INSTALL_DIR/rama.zip" -d "$RAMA_INSTALL_DIR"
rm -f "$RAMA_INSTALL_DIR/rama.zip"
chmod +x "$RAMA_INSTALL_DIR/rama"

cp /tmp/rama.yaml              "$RAMA_INSTALL_DIR/rama.yaml"
cp /tmp/rama-conductor.service /etc/systemd/system/rama-conductor.service
cp /tmp/rama-supervisor.service /etc/systemd/system/rama-supervisor.service

# ---------------------------------------------------------------------------
# 8. Start Zookeeper → Conductor → Supervisor
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable zookeeper rama-conductor rama-supervisor

systemctl start zookeeper
echo "Waiting for Zookeeper on port 2181..."
until (echo > /dev/tcp/127.0.0.1/2181) 2>/dev/null; do sleep 2; done
echo "Zookeeper ready."

systemctl start rama-conductor
echo "Waiting for Rama Conductor on port 1973..."
until (echo > /dev/tcp/127.0.0.1/1973) 2>/dev/null; do sleep 5; done
echo "Rama Conductor ready."

systemctl start rama-supervisor
echo "Waiting for Rama Supervisor to be active..."
until systemctl is-active --quiet rama-supervisor; do sleep 5; done
echo "Rama Supervisor active."

echo "Waiting 30 s for Supervisor to register with Conductor..."
sleep 30

# ---------------------------------------------------------------------------
# 9. Deploy monitoring module
# ---------------------------------------------------------------------------
/opt/rama/rama deploy \
  --action launch \
  --systemModule monitoring \
  --tasks 16 --threads 4 --workers 2 --replicationFactor 1

# ---------------------------------------------------------------------------
# 10. Download application JARs
# ---------------------------------------------------------------------------
echo "Downloading application JARs for commit ${git_sha} ..."

mkdir -p /opt/rama/modules
aws s3 cp \
  "s3://${deploy_bucket}/jars/backend/${git_sha}/mastodon-jar-with-dependencies.jar" \
  /opt/rama/modules/mastodon-jar-with-dependencies.jar \
  --region "${aws_region}" --no-progress

mkdir -p /opt/mastodon-api
aws s3 cp \
  "s3://${deploy_bucket}/jars/api/${git_sha}/mastodonapi.jar" \
  /opt/mastodon-api/mastodonapi.jar \
  --region "${aws_region}" --no-progress

echo "JARs downloaded."

# ---------------------------------------------------------------------------
# 11. Deploy Mastodon backend modules
# ---------------------------------------------------------------------------
BACKEND_JAR=/opt/rama/modules/mastodon-jar-with-dependencies.jar
DEPLOY_ARGS="--action launch --jar $BACKEND_JAR --tasks 16 --threads 4 --workers 1 --replicationFactor 1"

wait_for_module() {
  local module=$1
  echo "Waiting for module $module to reach RUNNING status..."
  while true; do
    status=$(/opt/rama/rama moduleStatus "$module" 2>/dev/null || true)
    if echo "$status" | grep -q '"moduleState":"RUNNING"'; then break; fi
    sleep 10
  done
  echo "Module $module is running."
}

for module in \
  com.rpl.mastodon.modules.Relationships \
  com.rpl.mastodon.modules.Core \
  com.rpl.mastodon.modules.GlobalTimelines \
  com.rpl.mastodon.modules.TrendsAndHashtags \
  com.rpl.mastodon.modules.Notifications \
  com.rpl.mastodon.modules.Search; do
  echo "Deploying $module ..."
  /opt/rama/rama deploy $DEPLOY_ARGS --module "$module"
  wait_for_module "$module"
done

echo "All Mastodon modules deployed."

# ---------------------------------------------------------------------------
# 12. Mastodon API service
# ---------------------------------------------------------------------------
cp /tmp/mastodon-api.service /etc/systemd/system/mastodon-api.service
mkdir -p /opt/mastodon-api/logs

systemctl daemon-reload
systemctl enable mastodon-api
systemctl start mastodon-api

echo "Mastodon API service started."

# ---------------------------------------------------------------------------
# 13. Soapbox frontend + Nginx
# ---------------------------------------------------------------------------
yum install -y nginx git

# Node 20 LTS
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs
npm install -g yarn

echo "Cloning Red Planet Labs Soapbox fork..."
git clone --depth 1 https://github.com/redplanetlabs/soapbox /tmp/soapbox-build

echo "Building Soapbox..."
cd /tmp/soapbox-build
yarn install --frozen-lockfile
NODE_ENV=production BACKEND_URL="http://127.0.0.1:8080" yarn build

mkdir -p /opt/soapbox
cp -r /tmp/soapbox-build/static/. /opt/soapbox/
rm -rf /tmp/soapbox-build
echo "Soapbox built and deployed to /opt/soapbox."

# Install nginx site config (rendered with domain by Terraform, uploaded to S3)
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
cp /tmp/nginx-soapbox.conf /etc/nginx/sites-available/soapbox
ln -sf /etc/nginx/sites-available/soapbox /etc/nginx/sites-enabled/soapbox
rm -f /etc/nginx/sites-enabled/default

# AL2023's nginx package doesn't include sites-enabled by default
if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
  sed -i '/include \/etc\/nginx\/conf\.d\/\*\.conf;/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
fi

nginx -t
systemctl enable nginx
systemctl start nginx

echo "Nginx started with Soapbox frontend."
echo "Bootstrap complete." >> "$LOG"
